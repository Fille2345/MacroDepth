// MacroDepthTests/NormalizedBoundingBoxTests.swift

import CoreGraphics
import Testing
@testable import MacroDepth

struct NormalizedBoundingBoxTests {
    @Test func parsesGeminiBox2DOrder() throws {
        // Gemini: [ymin, xmin, ymax, xmax] on 0…1000
        let box = try #require(NormalizedBoundingBox(geminiBox2D: [100, 200, 500, 800]))
        #expect(box.minX == 0.2)
        #expect(box.minY == 0.1)
        #expect(box.maxX == 0.8)
        #expect(box.maxY == 0.5)
        #expect(box.geminiBox2D == [100, 200, 500, 800])
    }

    @Test(arguments: [
        [Double](),
        [100, 200, 300],
        [500, 200, 100, 800],   // ymax < ymin
        [100, 800, 500, 200],   // xmax < xmin
        [100, 100, 101, 101],   // thinner than the minimum side
        [.nan, 0, 500, 500],
    ])
    func rejectsInvalidGeminiBoxes(values: [Double]) {
        #expect(NormalizedBoundingBox(geminiBox2D: values) == nil)
    }

    @Test func clampsSlightlyOutOfRangeValues() throws {
        let box = try #require(NormalizedBoundingBox(minX: -0.05, minY: 0.1, maxX: 1.02, maxY: 0.9))
        #expect(box.minX == 0)
        #expect(box.maxX == 1)
    }

    @Test func mapsToConcreteRect() throws {
        let box = try #require(NormalizedBoundingBox(minX: 0.25, minY: 0.5, maxX: 0.75, maxY: 1))
        let rect = box.rect(in: CGSize(width: 400, height: 300))
        #expect(rect == CGRect(x: 100, y: 150, width: 200, height: 150))
    }

    @Test func pixelRangesCoverPartialPixels() throws {
        let box = try #require(NormalizedBoundingBox(minX: 0.1, minY: 0.1, maxX: 0.5, maxY: 0.5))
        let ranges = try #require(box.pixelRanges(width: 256, height: 192))
        // 0.1·256 = 25.6 → 25 ; 0.5·256 = 128 ; 0.1·192 = 19.2 → 19 ; 0.5·192 = 96
        #expect(ranges.columns == 25..<128)
        #expect(ranges.rows == 19..<96)
        #expect(box.pixelRanges(width: 0, height: 10) == nil)
    }
}
