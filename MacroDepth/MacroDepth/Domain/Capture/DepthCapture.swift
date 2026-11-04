// Domain/Capture/DepthCapture.swift

import CoreGraphics
import Foundation
import simd

/// A depth raster copied out of an `ARFrame` (or synthesized for previews).
///
/// Layout is row-major, top-left origin, matching the captured image orientation.
/// Values are metric distance from the camera along its optical axis, in meters.
/// Plain arrays (not `CVPixelBuffer`) keep the type `Sendable` and independent of
/// ARKit, so the frame can be released immediately after capture.
struct DepthMap: Sendable, Equatable {
    /// Mirrors `ARConfidenceLevel` raw values.
    enum ConfidenceLevel: UInt8, Sendable, Comparable {
        case low = 0
        case medium = 1
        case high = 2

        static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let width: Int
    let height: Int
    let depthMeters: [Float]
    /// Per-pixel `ConfidenceLevel` raw values, or `nil` if unavailable.
    let confidence: [UInt8]?

    init?(width: Int, height: Int, depthMeters: [Float], confidence: [UInt8]? = nil) {
        guard width > 0, height > 0, depthMeters.count == width * height else { return nil }
        if let confidence, confidence.count != width * height { return nil }
        self.width = width
        self.height = height
        self.depthMeters = depthMeters
        self.confidence = confidence
    }

    func index(column: Int, row: Int) -> Int? {
        guard (0..<width).contains(column), (0..<height).contains(row) else { return nil }
        return row * width + column
    }

    /// Depth at a pixel, or `nil` if out of bounds or invalid (≤ 0, NaN, ∞).
    func depth(column: Int, row: Int) -> Float? {
        guard let index = index(column: column, row: row) else { return nil }
        let value = depthMeters[index]
        return value.isFinite && value > 0 ? value : nil
    }

    /// Confidence at a pixel; `.high` when no confidence map exists.
    func confidenceLevel(column: Int, row: Int) -> ConfidenceLevel? {
        guard let index = index(column: column, row: row) else { return nil }
        guard let confidence else { return .high }
        return ConfidenceLevel(rawValue: confidence[index]) ?? .low
    }

    /// The same map rotated 90° clockwise, as when a landscape sensor frame is shown
    /// upright on a portrait device. A sample at (column, row) moves to (height − 1 − row, column).
    func rotatedClockwise() -> DepthMap? {
        func rotate<Element>(_ source: [Element]) -> [Element] {
            var rotated: [Element] = []
            rotated.reserveCapacity(source.count)
            for newRow in 0..<width {
                for newColumn in 0..<height {
                    rotated.append(source[(height - 1 - newColumn) * width + newRow])
                }
            }
            return rotated
        }
        return DepthMap(
            width: height,
            height: width,
            depthMeters: rotate(depthMeters),
            confidence: confidence.map(rotate)
        )
    }

    /// Summary statistics over valid samples at or above `minimumConfidence`.
    func statistics(minimumConfidence: ConfidenceLevel = .low) -> DepthStatistics? {
        var samples: [Float] = []
        samples.reserveCapacity(depthMeters.count)
        for index in depthMeters.indices {
            let value = depthMeters[index]
            guard value.isFinite, value > 0 else { continue }
            if let confidence {
                let level = ConfidenceLevel(rawValue: confidence[index]) ?? .low
                guard level >= minimumConfidence else { continue }
            }
            samples.append(value)
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        let middle = samples.count / 2
        let median = samples.count.isMultiple(of: 2)
            ? (samples[middle - 1] + samples[middle]) / 2
            : samples[middle]
        return DepthStatistics(
            minimumMeters: samples[0],
            maximumMeters: samples[samples.count - 1],
            medianMeters: median,
            validSampleCount: samples.count,
            totalSampleCount: depthMeters.count
        )
    }
}

struct DepthStatistics: Sendable, Equatable {
    let minimumMeters: Float
    let maximumMeters: Float
    let medianMeters: Float
    let validSampleCount: Int
    let totalSampleCount: Int

    /// Fraction of pixels with usable depth.
    var coverage: Double {
        totalSampleCount > 0 ? Double(validSampleCount) / Double(totalSampleCount) : 0
    }
}

/// Pinhole camera intrinsics.
///
/// ```
///     | fx  0  cx |
/// K = |  0 fy  cy |      u = fx · X/Z + cx,   v = fy · Y/Z + cy
///     |  0  0   1 |
/// ```
/// Values are in pixels of `referenceResolution` (ARKit reports them for the
/// full captured image, e.g. 1920×1440). Use `scaled(to:)` before projecting into
/// the much smaller depth map.
struct CameraIntrinsics: Sendable, Equatable {
    let focalLengthX: Float
    let focalLengthY: Float
    let principalPointX: Float
    let principalPointY: Float
    let referenceResolution: CGSize

    init(focalLengthX: Float, focalLengthY: Float, principalPointX: Float, principalPointY: Float, referenceResolution: CGSize) {
        self.focalLengthX = focalLengthX
        self.focalLengthY = focalLengthY
        self.principalPointX = principalPointX
        self.principalPointY = principalPointY
        self.referenceResolution = referenceResolution
    }

    /// From ARKit's column-major `ARCamera.intrinsics`.
    init(matrix: simd_float3x3, referenceResolution: CGSize) {
        self.init(
            focalLengthX: matrix.columns.0.x,
            focalLengthY: matrix.columns.1.y,
            principalPointX: matrix.columns.2.x,
            principalPointY: matrix.columns.2.y,
            referenceResolution: referenceResolution
        )
    }

    var matrix: simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(focalLengthX, 0, 0),
            SIMD3<Float>(0, focalLengthY, 0),
            SIMD3<Float>(principalPointX, principalPointY, 1)
        ))
    }

    /// Intrinsics for the same camera at another resolution with the same aspect
    /// ratio (focal lengths and principal point scale linearly with pixel size).
    func scaled(to resolution: CGSize) -> CameraIntrinsics? {
        guard referenceResolution.width > 0, referenceResolution.height > 0,
              resolution.width > 0, resolution.height > 0 else { return nil }
        let scaleX = Float(resolution.width / referenceResolution.width)
        let scaleY = Float(resolution.height / referenceResolution.height)
        return CameraIntrinsics(
            focalLengthX: focalLengthX * scaleX,
            focalLengthY: focalLengthY * scaleY,
            principalPointX: principalPointX * scaleX,
            principalPointY: principalPointY * scaleY,
            referenceResolution: resolution
        )
    }

    /// Intrinsics for the image rotated 90° clockwise, where a pixel (u, v) moves to
    /// (height − v, u). Must be paired with `CameraPose.rotatedClockwise()`.
    func rotatedClockwise() -> CameraIntrinsics {
        CameraIntrinsics(
            focalLengthX: focalLengthY,
            focalLengthY: focalLengthX,
            principalPointX: Float(referenceResolution.height) - principalPointY,
            principalPointY: principalPointX,
            referenceResolution: CGSize(width: referenceResolution.height, height: referenceResolution.width)
        )
    }

    /// Back-projects pixel `(column, row)` at metric `depth` into camera space.
    /// The result uses *image-aligned* axes (x right, y down, z forward). ARKit's
    /// camera space is x right, y up, z backward, so flip y and z before applying
    /// an ARKit transform.
    func unproject(column: Float, row: Float, depth: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            (column - principalPointX) * depth / focalLengthX,
            (row - principalPointY) * depth / focalLengthY,
            depth
        )
    }
}

/// Camera-to-world transform stored as four `Sendable` SIMD columns.
struct CameraPose: Sendable, Equatable {
    let column0: SIMD4<Float>
    let column1: SIMD4<Float>
    let column2: SIMD4<Float>
    let column3: SIMD4<Float>

    static let identity = CameraPose(matrix: simd_float4x4(diagonal: SIMD4<Float>(repeating: 1)))

    init(matrix: simd_float4x4) {
        column0 = matrix.columns.0
        column1 = matrix.columns.1
        column2 = matrix.columns.2
        column3 = matrix.columns.3
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columns: (column0, column1, column2, column3))
    }

    /// The pose whose camera axes match an image rotated 90° clockwise: the new x axis
    /// (image right) is the sensor's +y, and the new y axis (image up) is the sensor's −x.
    func rotatedClockwise() -> CameraPose {
        let rotation = simd_float4x4(columns: (
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-1, 0, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
        return CameraPose(matrix: matrix * rotation)
    }

    var translation: SIMD3<Float> {
        SIMD3<Float>(column3.x, column3.y, column3.z)
    }
}

/// One scan session: a primary frame with depth, plus an optional angled photo.
///
/// `depthMap`, `intrinsics`, `cameraPose` and `imagePixelSize` all describe the
/// primary image, and detection boxes are expressed in its coordinates. That is
/// why the images aren't a flat array: only the primary one can be measured.
struct DepthCapture: Sendable, Identifiable {
    let id: UUID
    let capturedAt: Date
    /// JPEG of the top-down frame, already downscaled for upload.
    let imageJPEGData: Data
    /// JPEG of the optional angled (about 45°) photo. RGB context only: it has no depth.
    var secondaryImageJPEGData: Data?
    let imagePixelSize: CGSize
    /// `nil` on devices without LiDAR.
    let depthMap: DepthMap?
    let intrinsics: CameraIntrinsics?
    let cameraPose: CameraPose?

    init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        imageJPEGData: Data,
        secondaryImageJPEGData: Data? = nil,
        imagePixelSize: CGSize,
        depthMap: DepthMap?,
        intrinsics: CameraIntrinsics?,
        cameraPose: CameraPose?
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.imageJPEGData = imageJPEGData
        self.secondaryImageJPEGData = secondaryImageJPEGData
        self.imagePixelSize = imagePixelSize
        self.depthMap = depthMap
        self.intrinsics = intrinsics
        self.cameraPose = cameraPose
    }

    var hasDepth: Bool { depthMap != nil }

    /// Every image in upload order. The primary image always comes first.
    var allImagesJPEGData: [Data] {
        [imageJPEGData] + (secondaryImageJPEGData.map { [$0] } ?? [])
    }
}
