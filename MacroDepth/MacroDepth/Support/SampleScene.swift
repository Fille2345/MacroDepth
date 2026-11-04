// Support/SampleScene.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A synthetic plate of food: a rendered photo, a matching depth map, detections
/// and reference nutrition. It powers the Simulator, SwiftUI Previews and tests,
/// and later serves as ground truth for the volume-integration tests (Phase 3).
///
/// Geometry: a camera looks straight down at a table `tableDepthMeters` away.
/// A plate raises the surface by `plateHeightMeters`, and each food is a half
/// ellipsoid of height `heightMeters` on top of the plate.
enum SampleScene {
    struct Food: Sendable {
        let label: String
        let category: FoodCategory
        /// Center in image pixels, top-left origin.
        let center: CGPoint
        let radiusX: CGFloat
        let radiusY: CGFloat
        let heightMeters: Float
        let color: (red: CGFloat, green: CGFloat, blue: CGFloat)
        let macrosPer100Grams: MacroNutrients
        let densityGramsPerCubicCentimeter: Double
        let visualEstimateGrams: Double
        let detectionConfidence: Double
    }

    static let imageWidth = 1024
    static let imageHeight = 768
    /// Native LiDAR depth resolution on current iPhones.
    static let depthWidth = 256
    static let depthHeight = 192

    static let tableDepthMeters: Float = 0.45
    static let plateHeightMeters: Float = 0.012
    static let plateCenter = CGPoint(x: 512, y: 384)
    static let plateRadius: CGFloat = 330

    /// fx = fy = 0.75 × width approximates the iPhone wide camera's field of view.
    static let intrinsics = CameraIntrinsics(
        focalLengthX: 768,
        focalLengthY: 768,
        principalPointX: 512,
        principalPointY: 384,
        referenceResolution: CGSize(width: 1024, height: 768)
    )

    // Reference macros: available carbohydrate convention (fibre separate).
    static let foods: [Food] = [
        Food(
            label: "Steamed white rice",
            category: .grainOrStarch,
            center: CGPoint(x: 380, y: 300),
            radiusX: 140,
            radiusY: 110,
            heightMeters: 0.035,
            color: (0.96, 0.94, 0.86),
            macrosPer100Grams: MacroNutrients(proteinGrams: 2.7, carbohydrateGrams: 28, fatGrams: 0.3, fiberGrams: 0.4, energyKilocalories: 130),
            densityGramsPerCubicCentimeter: 0.85,
            visualEstimateGrams: 180,
            detectionConfidence: 0.90
        ),
        Food(
            label: "Grilled chicken breast",
            category: .meat,
            center: CGPoint(x: 655, y: 330),
            radiusX: 125,
            radiusY: 90,
            heightMeters: 0.025,
            color: (0.78, 0.56, 0.34),
            macrosPer100Grams: MacroNutrients(proteinGrams: 31, carbohydrateGrams: 0, fatGrams: 3.6, fiberGrams: 0, energyKilocalories: 165),
            densityGramsPerCubicCentimeter: 1.05,
            visualEstimateGrams: 140,
            detectionConfidence: 0.88
        ),
        Food(
            label: "Steamed broccoli",
            category: .vegetable,
            center: CGPoint(x: 520, y: 555),
            radiusX: 120,
            radiusY: 75,
            heightMeters: 0.040,
            color: (0.22, 0.52, 0.24),
            macrosPer100Grams: MacroNutrients(proteinGrams: 2.4, carbohydrateGrams: 3.9, fatGrams: 0.4, fiberGrams: 3.3, energyKilocalories: 35),
            densityGramsPerCubicCentimeter: 0.38,
            visualEstimateGrams: 90,
            detectionConfidence: 0.82
        ),
    ]

    // MARK: - Detections & reference data

    static func boundingBox(for food: Food) -> NormalizedBoundingBox {
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        return NormalizedBoundingBox(
            minX: Double(food.center.x - food.radiusX) / width,
            minY: Double(food.center.y - food.radiusY) / height,
            maxX: Double(food.center.x + food.radiusX) / width,
            maxY: Double(food.center.y + food.radiusY) / height
        ) ?? .fullFrame
    }

    /// Fresh detections (new UUIDs on every call, like a real request).
    static func sampleDetections() -> [DetectedFoodItem] {
        foods.map { food in
            DetectedFoodItem(
                label: food.label,
                category: food.category,
                boundingBox: boundingBox(for: food),
                confidence: food.detectionConfidence
            )
        }
    }

    static func referenceFood(matching label: String) -> Food? {
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return foods.first { $0.label.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Ready-made drafts using the photo-estimate path.
    static func sampleFoodItemDrafts() -> [FoodItemDraft] {
        foods.compactMap { food in
            guard let portion = PortionCalculator.portion(
                visualEstimateGrams: food.visualEstimateGrams,
                modelConfidence: food.detectionConfidence
            ) else { return nil }
            return FoodItemDraft(
                id: UUID(),
                name: food.label,
                category: food.category,
                portion: portion,
                macrosPer100Grams: food.macrosPer100Grams,
                boundingBox: boundingBox(for: food)
            )
        }
    }

    // MARK: - Capture

    static func makeCapture(includeDepth: Bool, capturedAt: Date = .now) throws -> DepthCapture {
        let jpeg = try renderJPEG()
        let depthMap: DepthMap?
        if includeDepth {
            guard let map = makeDepthMap() else { throw ScannerError.frameUnavailable }
            depthMap = map
        } else {
            depthMap = nil
        }
        return DepthCapture(
            capturedAt: capturedAt,
            imageJPEGData: jpeg,
            imagePixelSize: CGSize(width: imageWidth, height: imageHeight),
            depthMap: depthMap,
            intrinsics: intrinsics,
            cameraPose: .identity
        )
    }

    /// Renders the scene with Core Graphics only (thread-safe, no UIKit isolation).
    static func renderJPEG(compressionQuality: CGFloat = 0.8) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: imageWidth,
                  height: imageHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ScannerError.imageEncodingFailed
        }

        // Flip to a top-left origin so drawing matches image/box coordinates.
        context.translateBy(x: 0, y: CGFloat(imageHeight))
        context.scaleBy(x: 1, y: -1)

        // Table
        context.setFillColor(red: 0.47, green: 0.35, blue: 0.25, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        // Plate with rim
        let plateRect = CGRect(
            x: plateCenter.x - plateRadius,
            y: plateCenter.y - plateRadius,
            width: plateRadius * 2,
            height: plateRadius * 2
        )
        context.setFillColor(red: 0.86, green: 0.86, blue: 0.84, alpha: 1)
        context.fillEllipse(in: plateRect)
        context.setFillColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1)
        context.fillEllipse(in: plateRect.insetBy(dx: 24, dy: 24))

        // Food: base ellipse plus a lighter highlight to suggest volume
        for food in foods {
            let rect = CGRect(
                x: food.center.x - food.radiusX,
                y: food.center.y - food.radiusY,
                width: food.radiusX * 2,
                height: food.radiusY * 2
            )
            context.setFillColor(red: food.color.red * 0.85, green: food.color.green * 0.85, blue: food.color.blue * 0.85, alpha: 1)
            context.fillEllipse(in: rect)
            context.setFillColor(red: food.color.red, green: food.color.green, blue: food.color.blue, alpha: 1)
            context.fillEllipse(in: rect.insetBy(dx: food.radiusX * 0.15, dy: food.radiusY * 0.15))
        }

        guard let image = context.makeImage() else { throw ScannerError.imageEncodingFailed }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ScannerError.imageEncodingFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw ScannerError.imageEncodingFailed }
        return data as Data
    }

    /// Synthesizes a 256×192 depth map consistent with the rendered image.
    ///
    /// Each depth pixel samples the scene at its center in image coordinates.
    /// Surface height above the table is the plate height plus, inside a food's
    /// ellipse, the half-ellipsoid profile `h · √(1 − r²)` with
    /// `r² = (dx/rx)² + (dy/ry)²`. Depth is `table − height`. Pixels near a
    /// food's edge (r² > 0.85) get medium confidence, mimicking LiDAR's weaker
    /// returns on steep boundaries.
    static func makeDepthMap() -> DepthMap? {
        let scaleX = CGFloat(imageWidth) / CGFloat(depthWidth)
        let scaleY = CGFloat(imageHeight) / CGFloat(depthHeight)
        var depth = [Float](repeating: tableDepthMeters, count: depthWidth * depthHeight)
        var confidence = [UInt8](
            repeating: DepthMap.ConfidenceLevel.high.rawValue,
            count: depthWidth * depthHeight
        )

        for row in 0..<depthHeight {
            for column in 0..<depthWidth {
                let index = row * depthWidth + column
                let x = (CGFloat(column) + 0.5) * scaleX
                let y = (CGFloat(row) + 0.5) * scaleY

                var height: Float = 0
                let plateDX = x - plateCenter.x
                let plateDY = y - plateCenter.y
                if plateDX * plateDX + plateDY * plateDY <= plateRadius * plateRadius {
                    height = plateHeightMeters
                }

                for food in foods {
                    let normalizedX = (x - food.center.x) / food.radiusX
                    let normalizedY = (y - food.center.y) / food.radiusY
                    let radiusSquared = Float(normalizedX * normalizedX + normalizedY * normalizedY)
                    guard radiusSquared < 1 else { continue }
                    let foodHeight = plateHeightMeters + food.heightMeters * (1 - radiusSquared).squareRoot()
                    height = max(height, foodHeight)
                    if radiusSquared > 0.85 {
                        confidence[index] = DepthMap.ConfidenceLevel.medium.rawValue
                    }
                }

                depth[index] = tableDepthMeters - height
            }
        }

        return DepthMap(width: depthWidth, height: depthHeight, depthMeters: depth, confidence: confidence)
    }
}
