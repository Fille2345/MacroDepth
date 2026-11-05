// MacroDepthTests/VolumeCalculatorServiceTests.swift

import CoreGraphics
import Foundation
import Testing
import simd
@testable import MacroDepth

/// Renders mock depth by ray tracing real solids through a pinhole camera, so the
/// expected volumes come from geometry rather than from the code under test.
/// Coordinates are image-aligned camera space (x right, y down, z forward), in meters.
private struct MockDepthScene {
    enum Solid {
        /// Radii a (x) and b (y), height h. Only used on an untilted surface.
        case halfEllipsoid(center: SIMD2<Double>, a: Double, b: Double, height: Double)
        case halfSphere(center: SIMD2<Double>, radius: Double)
        case cylinder(center: SIMD2<Double>, radius: Double, height: Double)
    }

    static let width = 256
    static let height = 192
    /// Same field of view as an iPhone wide camera: fx = 0.75 × image width.
    static let intrinsics = CameraIntrinsics(
        focalLengthX: 1440,
        focalLengthY: 1440,
        principalPointX: 960,
        principalPointY: 720,
        referenceResolution: CGSize(width: 1920, height: 1440)
    )

    var surfaceDistance = 0.40
    /// Rotation of the surface about the camera's x axis, as when the phone isn't level.
    var tiltDegrees = 0.0
    var solids: [Solid] = []

    /// Points away from the camera.
    private var normal: SIMD3<Double> {
        let angle = tiltDegrees * .pi / 180
        return SIMD3(0, sin(angle), cos(angle))
    }

    /// Point on the surface at in-plane offset (x, y) from the optical axis.
    private func surfacePoint(_ offset: SIMD2<Double>) -> SIMD3<Double> {
        let along = simd_cross(normal, SIMD3(1, 0, 0))
        return SIMD3(0, 0, surfaceDistance) + SIMD3(offset.x, 0, 0) + along * -offset.y
    }

    /// Depth (z) where the ray through a pixel center first hits the scene.
    private func depth(column: Int, row: Int) -> Double {
        let camera = Self.intrinsics.scaled(to: CGSize(width: Self.width, height: Self.height))!
        let ray = SIMD3<Double>(
            (Double(column) + 0.5 - Double(camera.principalPointX)) / Double(camera.focalLengthX),
            (Double(row) + 0.5 - Double(camera.principalPointY)) / Double(camera.focalLengthY),
            1
        )
        var nearest = simd_dot(normal, SIMD3(0, 0, surfaceDistance)) / simd_dot(normal, ray)
        for solid in solids {
            if let hit = intersect(ray, solid), hit < nearest { nearest = hit }
        }
        return nearest
    }

    private func smallestPositiveRoot(a: Double, b: Double, c: Double) -> Double? {
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let root = (-b - discriminant.squareRoot()) / (2 * a)
        return root > 0 ? root : nil
    }

    private func intersect(_ ray: SIMD3<Double>, _ solid: Solid) -> Double? {
        switch solid {
        case .halfEllipsoid(let center, let radiusA, let radiusB, let height):
            let base = surfacePoint(center)
            let scale = SIMD3(1 / radiusA, 1 / radiusB, 1 / height)
            let scaledRay = ray * scale
            let scaledBase = base * scale
            guard let hit = smallestPositiveRoot(
                a: simd_dot(scaledRay, scaledRay),
                b: -2 * simd_dot(scaledRay, scaledBase),
                c: simd_dot(scaledBase, scaledBase) - 1
            ) else { return nil }
            return hit <= surfaceDistance ? hit : nil

        case .halfSphere(let center, let radius):
            let base = surfacePoint(center)
            guard let hit = smallestPositiveRoot(
                a: simd_dot(ray, ray),
                b: -2 * simd_dot(ray, base),
                c: simd_dot(base, base) - radius * radius
            ) else { return nil }
            return simd_dot(normal, base - ray * hit) >= 0 ? hit : nil

        case .cylinder(let center, let radius, let height):
            let base = surfacePoint(center)
            var best: Double?
            // Flat top
            let top = base - normal * height
            let capHit = simd_dot(normal, top) / simd_dot(normal, ray)
            let capOffset = ray * capHit - top
            if capHit > 0, simd_length_squared(capOffset) <= radius * radius {
                best = capHit
            }
            // Side wall, solved perpendicular to the axis
            let flatRay = ray - normal * simd_dot(ray, normal)
            let flatBase = base - normal * simd_dot(base, normal)
            if let wallHit = smallestPositiveRoot(
                a: simd_dot(flatRay, flatRay),
                b: -2 * simd_dot(flatRay, flatBase),
                c: simd_dot(flatBase, flatBase) - radius * radius
            ) {
                let rise = simd_dot(normal, base - ray * wallHit)
                if rise >= 0, rise <= height, wallHit < (best ?? .infinity) {
                    best = wallHit
                }
            }
            return best
        }
    }

    func makeDepthMeters() -> [Float] {
        var depths: [Float] = []
        depths.reserveCapacity(Self.width * Self.height)
        for row in 0..<Self.height {
            for column in 0..<Self.width {
                depths.append(Float(depth(column: column, row: row)))
            }
        }
        return depths
    }

    func makeDepthMap() throws -> DepthMap {
        try #require(DepthMap(width: Self.width, height: Self.height, depthMeters: makeDepthMeters()))
    }

    /// A box around a circle of `radius` at in-plane `center`, padded by `padding`,
    /// computed by projecting points on the surface and at `height` above it.
    func box(center: SIMD2<Double>, radiusX: Double, radiusY: Double, height: Double = 0, padding: Double = 0.01) throws -> NormalizedBoundingBox {
        var xs: [Double] = []
        var ys: [Double] = []
        for offsetX in [-radiusX - padding, radiusX + padding] {
            for offsetY in [-radiusY - padding, radiusY + padding] {
                for rise in [0, height] {
                    let point = surfacePoint(center + SIMD2(offsetX, offsetY)) - normal * rise
                    xs.append((point.x / point.z * 1440 + 960) / 1920)
                    ys.append((point.y / point.z * 1440 + 720) / 1440)
                }
            }
        }
        return try #require(NormalizedBoundingBox(minX: xs.min()!, minY: ys.min()!, maxX: xs.max()!, maxY: ys.max()!))
    }
}

private func expectClose(
    _ actual: Double,
    _ expected: Double,
    within fraction: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let error = abs(actual - expected) / expected
    #expect(error <= fraction, "Got \(actual), expected \(expected) (off by \(error * 100)%)", sourceLocation: sourceLocation)
}

struct VolumeCalculatorServiceTests {
    private let service = VolumeCalculatorService()
    private let center = SIMD2<Double>(0, 0)

    private func measure(_ scene: MockDepthScene, box: NormalizedBoundingBox, shape: FoodShape) throws -> FoodVolumeEstimate {
        try service.estimateVolume(in: box, shape: shape, depthMap: try scene.makeDepthMap(), intrinsics: MockDepthScene.intrinsics)
    }

    /// A half-sphere of radius 5 cm: ⅔π × 5³.
    private let domeVolume = 261.8
    /// One view can't see a dome's far edge, so its footprint and volume read low even
    /// when centered. Solids with a fully visible top don't have this error, as
    /// `tiltedFlatTopStaysAccurate` shows, so these tolerances are not hiding a math error.
    private let centeredDomeTolerance = 0.06

    // MARK: Known solids

    @Test func halfSphereMatchesTheFormula() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05), shape: .halfEllipsoid)

        expectClose(result.measurement.cubicCentimeters, domeVolume, within: centeredDomeTolerance)
        expectClose(result.widthCentimeters, 10, within: 0.05)
        expectClose(result.lengthCentimeters, 10, within: 0.05)
        expectClose(result.heightCentimeters, 5, within: 0.05)
        expectClose(result.footprintSquareCentimeters, 78.54, within: 0.05)
    }

    @Test func halfEllipsoidMatchesTheFormula() throws {
        let scene = MockDepthScene(solids: [.halfEllipsoid(center: center, a: 0.08, b: 0.06, height: 0.035)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.08, radiusY: 0.06), shape: .halfEllipsoid)

        // V = ⅔π × 8 × 6 × 3.5 = 351.9 cm³
        expectClose(result.measurement.cubicCentimeters, 351.9, within: 0.05)
        expectClose(result.widthCentimeters, 16, within: 0.05)
        expectClose(result.lengthCentimeters, 12, within: 0.05)
        expectClose(result.heightCentimeters, 3.5, within: 0.05)
    }

    @Test func cylinderMatchesTheFormula() throws {
        let scene = MockDepthScene(surfaceDistance: 0.45, solids: [.cylinder(center: center, radius: 0.035, height: 0.10)])
        let box = try scene.box(center: center, radiusX: 0.035, radiusY: 0.035, height: 0.10)
        let result = try measure(scene, box: box, shape: .cylinder)

        // V = π × 3.5² × 10 = 384.8 cm³
        expectClose(result.measurement.cubicCentimeters, 384.8, within: 0.05)
        expectClose(result.heightCentimeters, 10, within: 0.02)
        expectClose(result.widthCentimeters, 7, within: 0.05)
    }

    @Test func shapeOnlyChangesTheVolumeFactor() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)
        let pile = try measure(scene, box: box, shape: .halfEllipsoid)
        let glass = try measure(scene, box: box, shape: .cylinder)

        expectClose(glass.measurement.cubicCentimeters / pile.measurement.cubicCentimeters, 1.5, within: 1e-9)
        #expect(glass.footprintSquareCentimeters == pile.footprintSquareCentimeters)
    }

    // MARK: Capture conditions

    @Test(arguments: [0.30, 0.40, 0.60])
    func distanceFromThePlateDoesNotChangeTheVolume(distance: Double) throws {
        let scene = MockDepthScene(surfaceDistance: distance, solids: [.halfSphere(center: center, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, height: 0.05), shape: .halfEllipsoid)
        // Closer means a wider angle across the dome, which hides more of its edge.
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.08)
    }

    /// Tilt hides more of a dome's far side, so it reads lower as the angle grows.
    /// Only the length is affected, and the height stays accurate.
    @Test(arguments: [(5.0, 0.07), (15.0, 0.10), (25.0, 0.15)])
    func tiltedDomeReadsLowOnlyByWhatTheCameraCannotSee(degrees: Double, tolerance: Double) throws {
        let scene = MockDepthScene(tiltDegrees: degrees, solids: [.halfSphere(center: center, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, height: 0.05), shape: .halfEllipsoid)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: tolerance)
        #expect(result.measurement.cubicCentimeters < domeVolume)
        expectClose(result.heightCentimeters, 5, within: 0.02)
        expectClose(result.widthCentimeters, 10, within: 0.03)
    }

    /// Nothing is hidden on a flat-topped solid, so this checks the tilt math on its own.
    @Test(arguments: [0.0, 5.0, 15.0, 25.0, 40.0])
    func tiltedFlatTopStaysAccurate(degrees: Double) throws {
        let scene = MockDepthScene(tiltDegrees: degrees, solids: [.cylinder(center: center, radius: 0.05, height: 0.02)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, height: 0.02), shape: .cylinder)
        // V = π × 5² × 2 = 157.08 cm³
        expectClose(result.measurement.cubicCentimeters, 157.08, within: 0.02)
        expectClose(result.heightCentimeters, 2, within: 0.02)
    }

    @Test func surfaceTooSteepToBeAPlateIsRejected() throws {
        let scene = MockDepthScene(tiltDegrees: 55, solids: [.cylinder(center: center, radius: 0.05, height: 0.02)])
        #expect(throws: VolumeCalculationError.noReferenceSurface) {
            try measure(scene, box: try scene.box(center: center, radiusX: 0.03, radiusY: 0.03, height: 0.02), shape: .cylinder)
        }
    }

    @Test func itemAwayFromTheImageCenterStaysClose() throws {
        let offset = SIMD2<Double>(0.08, -0.06)
        let scene = MockDepthScene(solids: [.halfSphere(center: offset, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: offset, radiusX: 0.05, radiusY: 0.05, height: 0.05), shape: .halfEllipsoid)
        // Viewed at about 14° off vertical, so it loses about as much as a tilted dome.
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.10)
    }

    @Test func looseBoxDoesNotInflateTheVolume() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let loose = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, padding: 0.04)
        let result = try measure(scene, box: loose, shape: .halfEllipsoid)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: centeredDomeTolerance)
    }

    @Test func diagonalItemIsNotInflatedByItsBox() throws {
        // Two overlapping half-spheres along a diagonal fill only part of their box.
        let scene = MockDepthScene(solids: [
            .halfSphere(center: SIMD2(-0.03, -0.03), radius: 0.03),
            .halfSphere(center: SIMD2(0.03, 0.03), radius: 0.03),
            .halfSphere(center: center, radius: 0.03),
        ])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.06, radiusY: 0.06), shape: .halfEllipsoid)
        let boxFormula = 2.0 / 3.0 * .pi * 6 * 6 * result.heightCentimeters
        #expect(result.measurement.cubicCentimeters < boxFormula * 0.7)
    }

    // MARK: Neighbors

    @Test func neighborInsideTheBoxIsExcluded() throws {
        let neighbor = SIMD2<Double>(0.095, 0.095)
        let scene = MockDepthScene(solids: [
            .halfSphere(center: center, radius: 0.05),
            .halfSphere(center: neighbor, radius: 0.025),
        ])
        let box = try scene.box(center: center, radiusX: 0.09, radiusY: 0.09)
        let result = try measure(scene, box: box, shape: .halfEllipsoid)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: centeredDomeTolerance)
    }

    @Test func neighborInTheRingDoesNotLiftTheSurface() throws {
        let scene = MockDepthScene(solids: [
            .halfSphere(center: center, radius: 0.05),
            .halfSphere(center: SIMD2(0.075, 0), radius: 0.025),
        ])
        // Tight box, with the neighbor filling one side of the ring.
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, padding: 0)
        let result = try measure(scene, box: box, shape: .halfEllipsoid)
        expectClose(result.heightCentimeters, 5, within: 0.05)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.12)
    }

    // MARK: Real-world depth problems

    @Test func sensorNoiseKeepsTheVolumeClose() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        var depths = scene.makeDepthMeters()
        // A fixed sequence of about ±1.5 mm, repeatable from run to run.
        var state: UInt32 = 12345
        for index in depths.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            let unit = Float(state >> 16 & 0xFFFF) / 65_535
            depths[index] += (unit - 0.5) * 0.003
        }
        let map = try #require(DepthMap(width: MockDepthScene.width, height: MockDepthScene.height, depthMeters: depths))
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)
        let result = try service.estimateVolume(in: box, shape: .halfEllipsoid, depthMap: map, intrinsics: MockDepthScene.intrinsics)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.08)
    }

    @Test func depthDropoutsInsideTheItemAreFilled() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        var depths = scene.makeDepthMeters()
        // Lose every 10th pixel, plus a block in the middle of the item.
        for index in depths.indices where index % 10 == 3 {
            depths[index] = .nan
        }
        for row in 92..<100 {
            for column in 124..<132 {
                depths[row * MockDepthScene.width + column] = 0
            }
        }
        let map = try #require(DepthMap(width: MockDepthScene.width, height: MockDepthScene.height, depthMeters: depths))
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)
        let result = try service.estimateVolume(in: box, shape: .halfEllipsoid, depthMap: map, intrinsics: MockDepthScene.intrinsics)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.07)
    }

    @Test func lowConfidenceSamplesAreIgnored() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let depths = scene.makeDepthMeters()
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)

        let allLow = [UInt8](repeating: DepthMap.ConfidenceLevel.low.rawValue, count: depths.count)
        let lowMap = try #require(DepthMap(width: MockDepthScene.width, height: MockDepthScene.height, depthMeters: depths, confidence: allLow))
        #expect(throws: VolumeCalculationError.insufficientDepthData) {
            try service.estimateVolume(in: box, shape: .halfEllipsoid, depthMap: lowMap, intrinsics: MockDepthScene.intrinsics)
        }

        let allMedium = [UInt8](repeating: DepthMap.ConfidenceLevel.medium.rawValue, count: depths.count)
        let mediumMap = try #require(DepthMap(width: MockDepthScene.width, height: MockDepthScene.height, depthMeters: depths, confidence: allMedium))
        let result = try service.estimateVolume(in: box, shape: .halfEllipsoid, depthMap: mediumMap, intrinsics: MockDepthScene.intrinsics)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: centeredDomeTolerance)
    }

    // MARK: Failures

    @Test func emptyPlateHasNoFoodToMeasure() throws {
        let scene = MockDepthScene()
        #expect(throws: VolumeCalculationError.noFoodAboveSurface) {
            try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05), shape: .halfEllipsoid)
        }
    }

    @Test func foodThinnerThanSensorNoiseIsNotMeasured() throws {
        let scene = MockDepthScene(solids: [.cylinder(center: center, radius: 0.05, height: 0.003)])
        #expect(throws: VolumeCalculationError.noFoodAboveSurface) {
            try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05), shape: .cylinder)
        }
    }

    @Test func boxFillingTheFrameHasNoSurfaceToMeasureFrom() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        #expect(throws: VolumeCalculationError.noReferenceSurface) {
            try measure(scene, box: .fullFrame, shape: .halfEllipsoid)
        }
    }

    @Test func missingDepthInTheBoxIsReported() throws {
        let scene = MockDepthScene()
        let map = try #require(DepthMap(
            width: MockDepthScene.width,
            height: MockDepthScene.height,
            depthMeters: [Float](repeating: .nan, count: MockDepthScene.width * MockDepthScene.height)
        ))
        #expect(throws: VolumeCalculationError.insufficientDepthData) {
            try service.estimateVolume(
                in: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05),
                shape: .halfEllipsoid,
                depthMap: map,
                intrinsics: MockDepthScene.intrinsics
            )
        }
    }

    @Test func intrinsicsForADifferentFieldOfViewAreRejected() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let wrongAspect = CameraIntrinsics(
            focalLengthX: 1440,
            focalLengthY: 1440,
            principalPointX: 960,
            principalPointY: 540,
            referenceResolution: CGSize(width: 1920, height: 1080)
        )
        #expect(throws: VolumeCalculationError.invalidIntrinsics) {
            try service.estimateVolume(
                in: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05),
                shape: .halfEllipsoid,
                depthMap: try scene.makeDepthMap(),
                intrinsics: wrongAspect
            )
        }
    }

    // MARK: No surface to measure from

    /// A portrait-style scene: floor at 1.57 m, a bed at 0.8–1.1 m, a hand at 0.22–0.30 m
    /// and a banana at 0.19–0.23 m. It's the capture that once read 138 cm tall.
    private func handHeldBanana(floorOnlyAround: Bool = false, bananaHeightAboveFloor: Float? = nil) throws -> DepthMap {
        let width = MockDepthScene.width
        let height = MockDepthScene.height
        var depths = [Float](repeating: 1.57, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                if !floorOnlyAround {
                    if column > 150 { depths[index] = 0.8 + Float(column - 150) * 0.003 }
                    if row > 110, column > 70, column < 190 { depths[index] = 0.22 + Float(row - 110) * 0.001 }
                }
                if row > 70, row < 115, column > 80, column < 180 {
                    let surface = bananaHeightAboveFloor.map { 1.57 - $0 } ?? 0.19
                    depths[index] = surface + abs(Float(row - 92)) * 0.002
                }
            }
        }
        return try #require(DepthMap(width: width, height: height, depthMeters: depths))
    }

    private let bananaBox = NormalizedBoundingBox(minX: 80.0 / 256, minY: 70.0 / 192, maxX: 180.0 / 256, maxY: 115.0 / 192)!

    @Test func handAndFloorInTheRingAreRejected() throws {
        let map = try handHeldBanana()
        #expect(throws: VolumeCalculationError.noReferenceSurface) {
            try service.estimateVolume(in: bananaBox, shape: .halfEllipsoid, depthMap: map, intrinsics: MockDepthScene.intrinsics)
        }
    }

    /// The ring's variance is tiny here, so the height check has to catch it.
    @Test func itemFarAboveAFlatFloorIsRejected() throws {
        let map = try handHeldBanana(floorOnlyAround: true)
        #expect(throws: VolumeCalculationError.noReferenceSurface) {
            try service.estimateVolume(in: bananaBox, shape: .halfEllipsoid, depthMap: map, intrinsics: MockDepthScene.intrinsics)
        }
    }

    /// Low enough to be believable food, but its edges never reach the surface.
    @Test(arguments: [FoodShape.halfEllipsoid, .slab])
    func itemFloatingJustAboveASurfaceIsRejected(shape: FoodShape) throws {
        let map = try handHeldBanana(floorOnlyAround: true, bananaHeightAboveFloor: 0.25)
        #expect(throws: VolumeCalculationError.noReferenceSurface) {
            try service.estimateVolume(in: bananaBox, shape: shape, depthMap: map, intrinsics: MockDepthScene.intrinsics)
        }
    }

    /// Seen from straight above, a glass's top floats over the table, and that's still valid.
    @Test func glassSeenFromAboveIsNotTreatedAsFloating() throws {
        let scene = MockDepthScene(surfaceDistance: 0.45, solids: [.cylinder(center: center, radius: 0.035, height: 0.15)])
        let box = try scene.box(center: center, radiusX: 0.035, radiusY: 0.035, height: 0.15)
        let result = try measure(scene, box: box, shape: .cylinder)
        expectClose(result.heightCentimeters, 15, within: 0.02)
    }

    @Test func tiltedPlateWithANeighborStillPassesTheVarianceCheck() throws {
        let scene = MockDepthScene(tiltDegrees: 35, solids: [
            .halfSphere(center: center, radius: 0.05),
            .halfSphere(center: SIMD2(0.075, 0), radius: 0.025),
        ])
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, height: 0.05, padding: 0)
        let result = try measure(scene, box: box, shape: .halfEllipsoid)
        #expect(result.measurement.cubicCentimeters > 150 && result.measurement.cubicCentimeters < 320)
    }

    @Test func planeFitStopsAtItsTimeLimit() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)
        #expect(throws: VolumeCalculationError.planeFitTimedOut) {
            try VolumeCalculatorService(planeFitTimeLimit: .zero).estimateVolume(
                in: box,
                shape: .halfEllipsoid,
                depthMap: try scene.makeDepthMap(),
                intrinsics: MockDepthScene.intrinsics
            )
        }
    }

    @Test func thinningALargeRingKeepsTheResult() throws {
        // A big box has a ring far larger than the fit's sample limit.
        let scene = MockDepthScene(surfaceDistance: 0.6, solids: [.halfSphere(center: center, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05, padding: 0.14), shape: .halfEllipsoid)
        expectClose(result.measurement.cubicCentimeters, domeVolume, within: 0.08)
    }

    // MARK: Output

    @Test func reportsTheMethodSamplesAndUncertainty() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.05, radiusY: 0.05), shape: .halfEllipsoid)

        #expect(result.measurement.method == .shapeHeuristic)
        #expect(result.measurement.sampleCount > 1_000)
        #expect(result.measurement.relativeUncertainty >= FoodShape.halfEllipsoid.relativeUncertainty)
        #expect(result.measurement.relativeUncertainty < 0.35)
    }

    @Test func eachCategoryGetsItsShape() {
        #expect(FoodShape(category: .soupOrLiquid) == .cylinder)
        #expect(FoodShape(category: .dairy) == .cylinder)
        for category in [FoodCategory.meat, .fish, .cheese, .bakedGood] {
            #expect(FoodShape(category: category) == .slab)
        }
        #expect(FoodShape(category: .grainOrStarch) == .halfEllipsoid)
        #expect(FoodShape(category: .vegetable) == .halfEllipsoid)
    }

    @Test func slabIsFootprintTimesHeight() throws {
        let scene = MockDepthScene(solids: [.cylinder(center: center, radius: 0.06, height: 0.02)])
        let result = try measure(scene, box: try scene.box(center: center, radiusX: 0.06, radiusY: 0.06, height: 0.02), shape: .slab)
        // π × 6² × 2 = 226.2 cm³
        expectClose(result.measurement.cubicCentimeters, 226.2, within: 0.02)
        #expect(result.shape == .slab)
    }

    /// The case to check against a scale: a domed cut measured as a slab reads 1.5× its true volume.
    @Test func slabOverstatesADomeByHalf() throws {
        let scene = MockDepthScene(solids: [.halfSphere(center: center, radius: 0.05)])
        let box = try scene.box(center: center, radiusX: 0.05, radiusY: 0.05)
        let slab = try measure(scene, box: box, shape: .slab)
        let pile = try measure(scene, box: box, shape: .halfEllipsoid)
        expectClose(slab.measurement.cubicCentimeters / pile.measurement.cubicCentimeters, 1.5, within: 1e-9)
    }

    // MARK: Against the app's sample scene

    /// `SampleScene` foods are half ellipsoids whose radii are defined in image pixels.
    private func sampleSceneVolume(of food: SampleScene.Food) -> Double {
        let plateDepth = Double(SampleScene.tableDepthMeters - SampleScene.plateHeightMeters)
        let focal = Double(SampleScene.intrinsics.focalLengthX)
        let radiusX = Double(food.radiusX) * plateDepth / focal
        let radiusY = Double(food.radiusY) * plateDepth / focal
        return 2.0 / 3.0 * .pi * radiusX * radiusY * Double(food.heightMeters) * 1_000_000
    }

    @Test(arguments: SampleScene.foods.map(\.label))
    func measuresEachFoodInTheSampleScene(label: String) throws {
        let food = try #require(SampleScene.referenceFood(matching: label))
        let map = try #require(SampleScene.makeDepthMap())
        let result = try service.estimateVolume(
            in: SampleScene.boundingBox(for: food),
            shape: .halfEllipsoid,
            depthMap: map,
            intrinsics: SampleScene.intrinsics
        )
        expectClose(result.measurement.cubicCentimeters, sampleSceneVolume(of: food), within: 0.08)
        expectClose(result.heightCentimeters, Double(food.heightMeters) * 100, within: 0.05)
    }

    /// The scanner rotates depth and intrinsics to portrait, and boxes come from the
    /// upright photo. This checks the three still line up after that rotation.
    @Test func portraitCaptureMeasuresTheSameAsLandscape() throws {
        let food = try #require(SampleScene.referenceFood(matching: "Steamed white rice"))
        let box = SampleScene.boundingBox(for: food)
        let map = try #require(SampleScene.makeDepthMap())
        let landscape = try service.estimateVolume(in: box, shape: .halfEllipsoid, depthMap: map, intrinsics: SampleScene.intrinsics)

        let rotatedMap = try #require(map.rotatedClockwise())
        // A point (x, y) moves to (1 − y, x) when rotated clockwise.
        let rotatedBox = try #require(NormalizedBoundingBox(minX: 1 - box.maxY, minY: box.minX, maxX: 1 - box.minY, maxY: box.maxX))
        let portrait = try service.estimateVolume(
            in: rotatedBox,
            shape: .halfEllipsoid,
            depthMap: rotatedMap,
            intrinsics: SampleScene.intrinsics.rotatedClockwise()
        )

        expectClose(portrait.measurement.cubicCentimeters, landscape.measurement.cubicCentimeters, within: 0.01)
        // The item's width and length swap with the image's axes.
        expectClose(portrait.lengthCentimeters, landscape.widthCentimeters, within: 0.03)
    }
}
