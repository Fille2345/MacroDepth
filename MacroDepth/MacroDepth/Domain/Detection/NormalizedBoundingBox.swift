// Domain/Detection/NormalizedBoundingBox.swift

import CoreGraphics
import Foundation

/// Axis-aligned rectangle in normalized image coordinates.
///
/// Origin is top-left, x grows right, y grows down, all values in [0, 1].
/// This matches SwiftUI/UIKit image space and the row-major pixel layout of
/// ARKit's captured image and depth map (before any display-orientation transform),
/// so the same box can index both the photo and the 256×192 depth buffer.
struct NormalizedBoundingBox: Sendable, Hashable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    /// Smallest accepted side length; anything smaller is treated as noise.
    static let minimumSide = 0.005

    static let fullFrame = NormalizedBoundingBox(uncheckedMinX: 0, minY: 0, maxX: 1, maxY: 1)

    /// Validating initializer. Values are clamped to [0, 1]; returns `nil` for
    /// non-finite input, inverted boxes or boxes thinner than `minimumSide`.
    init?(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        guard [minX, minY, maxX, maxY].allSatisfy(\.isFinite) else { return nil }
        let clampedMinX = minX.clampedToUnitInterval
        let clampedMinY = minY.clampedToUnitInterval
        let clampedMaxX = maxX.clampedToUnitInterval
        let clampedMaxY = maxY.clampedToUnitInterval
        guard clampedMaxX - clampedMinX >= Self.minimumSide,
              clampedMaxY - clampedMinY >= Self.minimumSide else { return nil }
        self.init(uncheckedMinX: clampedMinX, minY: clampedMinY, maxX: clampedMaxX, maxY: clampedMaxY)
    }

    /// Gemini returns `box_2d` as `[ymin, xmin, ymax, xmax]` scaled to 0…1000.
    init?(geminiBox2D values: [Double]) {
        guard values.count == 4 else { return nil }
        self.init(
            minX: values[1] / 1000,
            minY: values[0] / 1000,
            maxX: values[3] / 1000,
            maxY: values[2] / 1000
        )
    }

    private init(uncheckedMinX minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// Inverse of `init(geminiBox2D:)`, used when describing boxes back to the model.
    var geminiBox2D: [Int] {
        [minY, minX, maxY, maxX].map { Int(($0 * 1000).rounded()) }
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var area: Double { width * height }
    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }

    /// The box in a concrete coordinate space of `size` (e.g. a SwiftUI frame).
    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    /// Pixel index ranges covered by the box in a raster of `width × height`
    /// (e.g. the LiDAR depth map). Edges are expanded outward so partially
    /// covered pixels are included. Returns `nil` if the raster is empty.
    func pixelRanges(width: Int, height: Int) -> (columns: Range<Int>, rows: Range<Int>)? {
        guard width > 0, height > 0 else { return nil }
        let firstColumn = max(0, Int((minX * Double(width)).rounded(.down)))
        let lastColumn = min(width, Int((maxX * Double(width)).rounded(.up)))
        let firstRow = max(0, Int((minY * Double(height)).rounded(.down)))
        let lastRow = min(height, Int((maxY * Double(height)).rounded(.up)))
        guard firstColumn < lastColumn, firstRow < lastRow else { return nil }
        return (firstColumn..<lastColumn, firstRow..<lastRow)
    }
}
