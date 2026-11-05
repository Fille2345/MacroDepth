// Services/Measurement/VolumeCalculatorService.swift

import Foundation
import simd

/// The simple solid used to turn a measured footprint and height into a volume.
enum FoodShape: String, Sendable, Hashable, CaseIterable {
    /// A pile of food, such as rice. A half-sphere is the special case with equal radii.
    case halfEllipsoid
    /// Straight sides and a flat top, such as a drink in a glass.
    case cylinder
    /// A flat piece of even thickness, such as a steak, a fillet or a slice of bread.
    /// A slab has the same formula as a cylinder, but it's a different assumption with
    /// a different margin of error: real cuts are often domed, which makes this read high.
    case slab

    /// Liquids sit in straight-sided containers and flat cuts have even thickness.
    /// Everything else is treated as a pile.
    init(category: FoodCategory) {
        switch category {
        case .soupOrLiquid, .dairy: self = .cylinder
        case .meat, .fish, .cheese, .bakedGood: self = .slab
        default: self = .halfEllipsoid
        }
    }

    var displayName: String {
        switch self {
        case .halfEllipsoid: "Pile"
        case .cylinder: "Cylinder"
        case .slab: "Slab"
        }
    }

    /// Volume ÷ (footprint area × height). For a half-ellipsoid with radii a, b and
    /// height h, V = ⅔πabh and the footprint is πab. For a cylinder, V = area × h.
    var volumeFactor: Double {
        switch self {
        case .halfEllipsoid: 2.0 / 3.0
        case .cylinder, .slab: 1
        }
    }

    /// How far real food may differ from the ideal solid, as a fraction of its volume.
    /// These are starting estimates, to be calibrated against weighed meals.
    var relativeUncertainty: Double {
        switch self {
        case .halfEllipsoid, .slab: 0.25
        case .cylinder: 0.10
        }
    }
}

/// One item's measured size and volume.
struct FoodVolumeEstimate: Sendable, Hashable {
    let measurement: VolumeMeasurement
    let shape: FoodShape
    /// Extent along the image's horizontal direction, on the reference surface.
    let widthCentimeters: Double
    /// Extent front to back on the reference surface, perpendicular to the width.
    let lengthCentimeters: Double
    /// Height above the reference surface.
    let heightCentimeters: Double
    let footprintSquareCentimeters: Double
}

protocol VolumeCalculatorServiceProtocol: Sendable {
    /// Measures the food inside `box`. `depthMap` and `intrinsics` must describe the
    /// same frame as the box, which is the capture's top-down photo.
    func estimateVolume(
        in box: NormalizedBoundingBox,
        shape: FoodShape,
        depthMap: DepthMap,
        intrinsics: CameraIntrinsics
    ) throws -> FoodVolumeEstimate
}

/// Depth-to-volume math.
///
/// 1. Fit the plate or table as a plane to the depth samples in a ring around the box.
/// 2. Measure each sample inside the box as a height above that plane. Using the plane
///    rather than raw depth differences means a tilted phone doesn't change the result.
/// 3. Keep the largest connected area of food, which removes neighbors and plate rims
///    caught in a loose box.
/// 4. Apply `V = volumeFactor × footprint area × height`.
///
/// A plate scan needs a surface the item rests on. Food held in a hand has none, so
/// a scene is rejected when the ring isn't one surface, or when the item is too tall
/// for food or floats above the surface. It then falls back to a photo estimate.
///
/// Using the measured footprint rather than the box's width and height means a loose
/// box or a diagonal item doesn't inflate the volume. The footprint is the outline of
/// the item's 3D edge points on the plane, not a sum of per-pixel areas: on a dome's
/// steep sides a pixel covers far more of the plate than its depth alone implies, and
/// summing undercounted a half-sphere by 16%.
struct VolumeCalculatorService: VolumeCalculatorServiceProtocol {
    // Starting values, to be tuned against real LiDAR captures.

    /// Lower-confidence samples are treated as missing.
    static let minimumConfidence = DepthMap.ConfidenceLevel.medium
    /// Fraction of the box that must have usable depth.
    static let minimumBoxCoverage = 0.3
    /// Width of the surface-fitting ring, as a fraction of the box's side.
    static let ringMarginFraction = 0.2
    static let minimumRingMarginPixels = 3
    static let minimumRingSamples = 30
    /// A sample within this distance of a candidate plane counts as on it.
    static let planeInlierThresholdMeters = 0.004
    /// The share of ring samples that must lie on the fitted plane.
    static let minimumPlaneInlierFraction = 0.4
    /// A steeper "surface" is more likely a wall or the side of a bowl than a plate.
    static let maximumPlaneTiltDegrees = 45.0
    static let planeSearchTrials = 128
    /// A larger ring is thinned evenly. It's still plenty for a plane, and bounds the search's work.
    static let maximumRingSamplesForFit = 1_500
    /// Scatter of the ring around its best-fit plane, in m². This is 5 cm one-sigma: well
    /// above a plate with neighboring food, far below a hand against a floor. It's measured
    /// around a plane rather than as raw depth variance, so a tilted phone isn't penalized.
    static let maximumRingVariance = 0.0025
    /// A deeper "item" means the surface found is a floor or bed, not what the food rests on.
    static let maximumFoodHeightMeters = 0.30
    /// A resting item's visible edge comes down to the surface. Otherwise it's in the air.
    /// Doesn't apply to cylinders: from above, only a glass's raised top may be visible.
    static let maximumGapBelowFoodMeters = 0.05
    /// Anything lower than this can't be told apart from sensor noise.
    static let minimumFoodHeightMeters = 0.005
    static let minimumFoodSamples = 12
    /// Height is a high percentile rather than the maximum, so one noisy spike can't set it.
    static let heightPercentile = 0.98
    /// Assumed one-sigma LiDAR depth noise at plate distance.
    static let depthNoiseMeters = 0.003

    private let planeFitTimeLimit: Duration

    init(planeFitTimeLimit: Duration = .milliseconds(100)) {
        self.planeFitTimeLimit = planeFitTimeLimit
    }

    func estimateVolume(
        in box: NormalizedBoundingBox,
        shape: FoodShape,
        depthMap: DepthMap,
        intrinsics: CameraIntrinsics
    ) throws -> FoodVolumeEstimate {
        guard let ranges = box.pixelRanges(width: depthMap.width, height: depthMap.height) else {
            throw VolumeCalculationError.insufficientDepthData
        }
        let camera = try Self.intrinsicsForDepthMap(intrinsics, depthMap: depthMap)

        let boxSamples = Self.samples(columns: ranges.columns, rows: ranges.rows, depthMap: depthMap, camera: camera)
        let boxPixelCount = ranges.columns.count * ranges.rows.count
        guard Double(boxSamples.count) / Double(boxPixelCount) >= Self.minimumBoxCoverage else {
            throw VolumeCalculationError.insufficientDepthData
        }

        let ring = Self.ringSamples(around: ranges, depthMap: depthMap, camera: camera)
        let plane = try Self.fitReferencePlane(to: ring, timeLimit: planeFitTimeLimit)

        let food = Self.largestConnectedFood(in: boxSamples, plane: plane)
        guard food.count >= Self.minimumFoodSamples else {
            throw VolumeCalculationError.noFoodAboveSurface
        }

        let footprint = Self.footprint(of: food, on: plane, camera: camera)
        let heights = food.map { plane.height(of: $0.position) }
        let height = Self.percentile(Self.heightPercentile, of: heights)
        guard height <= Self.maximumFoodHeightMeters,
              shape == .cylinder || (heights.min() ?? 0) <= Self.maximumGapBelowFoodMeters else {
            throw VolumeCalculationError.noReferenceSurface
        }

        let cubicMeters = shape.volumeFactor * footprint.area * height
        let cubicCentimeters = cubicMeters * 1_000_000
        let relativeUncertainty = Self.relativeUncertainty(
            shape: shape,
            sampleCount: food.count,
            height: height,
            planeResidual: plane.residual
        )
        guard let measurement = VolumeMeasurement(
            cubicCentimeters: cubicCentimeters,
            uncertaintyCubicCentimeters: cubicCentimeters * relativeUncertainty,
            sampleCount: food.count,
            method: .shapeHeuristic
        ) else {
            throw VolumeCalculationError.noFoodAboveSurface
        }

        return FoodVolumeEstimate(
            measurement: measurement,
            shape: shape,
            widthCentimeters: footprint.width * 100,
            lengthCentimeters: footprint.length * 100,
            heightCentimeters: height * 100,
            footprintSquareCentimeters: footprint.area * 10_000
        )
    }

    // MARK: Samples

    /// A usable depth pixel and its 3D position in image-aligned camera space
    /// (x right, y down, z forward), in meters.
    private struct Sample {
        let column: Int
        let row: Int
        let position: SIMD3<Double>
    }

    private static func intrinsicsForDepthMap(_ intrinsics: CameraIntrinsics, depthMap: DepthMap) throws -> CameraIntrinsics {
        let reference = intrinsics.referenceResolution
        guard reference.width > 0, reference.height > 0, intrinsics.focalLengthX > 0, intrinsics.focalLengthY > 0 else {
            throw VolumeCalculationError.invalidIntrinsics
        }
        // The box indexes both rasters, so they must show the same field of view.
        let referenceAspect = reference.width / reference.height
        let depthAspect = CGFloat(depthMap.width) / CGFloat(depthMap.height)
        guard abs(referenceAspect - depthAspect) / depthAspect <= 0.02,
              let scaled = intrinsics.scaled(to: CGSize(width: depthMap.width, height: depthMap.height)) else {
            throw VolumeCalculationError.invalidIntrinsics
        }
        return scaled
    }

    private static func sample(column: Int, row: Int, depthMap: DepthMap, camera: CameraIntrinsics) -> Sample? {
        guard let depth = depthMap.depth(column: column, row: row),
              let confidence = depthMap.confidenceLevel(column: column, row: row),
              confidence >= minimumConfidence else { return nil }
        // Pixel centers sit at +0.5 in the intrinsics' coordinate system.
        let position = camera.unproject(column: Float(column) + 0.5, row: Float(row) + 0.5, depth: depth)
        return Sample(column: column, row: row, position: SIMD3<Double>(position))
    }

    private static func samples(columns: Range<Int>, rows: Range<Int>, depthMap: DepthMap, camera: CameraIntrinsics) -> [Sample] {
        var samples: [Sample] = []
        samples.reserveCapacity(columns.count * rows.count)
        for row in rows {
            for column in columns {
                if let sample = sample(column: column, row: row, depthMap: depthMap, camera: camera) {
                    samples.append(sample)
                }
            }
        }
        return samples
    }

    private static func ringSamples(
        around ranges: (columns: Range<Int>, rows: Range<Int>),
        depthMap: DepthMap,
        camera: CameraIntrinsics
    ) -> [Sample] {
        let marginX = max(minimumRingMarginPixels, Int((Double(ranges.columns.count) * ringMarginFraction).rounded(.up)))
        let marginY = max(minimumRingMarginPixels, Int((Double(ranges.rows.count) * ringMarginFraction).rounded(.up)))
        let columns = max(0, ranges.columns.lowerBound - marginX)..<min(depthMap.width, ranges.columns.upperBound + marginX)
        let rows = max(0, ranges.rows.lowerBound - marginY)..<min(depthMap.height, ranges.rows.upperBound + marginY)
        return samples(columns: columns, rows: rows, depthMap: depthMap, camera: camera).filter {
            !(ranges.columns.contains($0.column) && ranges.rows.contains($0.row))
        }
    }

    // MARK: Reference plane

    /// The plate or table, with its normal pointing away from the camera.
    private struct Plane {
        let normal: SIMD3<Double>
        let offset: Double
        /// RMS distance of the samples it was fitted to.
        var residual = 0.0

        /// Height above the plane, positive toward the camera.
        func height(of point: SIMD3<Double>) -> Double {
            offset - simd_dot(normal, point)
        }
    }

    /// Finds the plane most ring samples agree on, then refines it with least squares.
    /// Picking by agreement means neighboring food in the ring can't pull the plane up.
    private static func fitReferencePlane(to ring: [Sample], timeLimit: Duration) throws -> Plane {
        guard ring.count >= minimumRingSamples else {
            throw VolumeCalculationError.noReferenceSurface
        }
        let stride = max(1, ring.count / maximumRingSamplesForFit)
        let points = Swift.stride(from: 0, to: ring.count, by: stride).map { ring[$0].position }

        // One pass over the ring, so a scene that isn't one surface is rejected before any search.
        guard let overall = leastSquaresPlane(through: points),
              overall.residual * overall.residual <= maximumRingVariance else {
            throw VolumeCalculationError.noReferenceSurface
        }

        let deadline = ContinuousClock.now + timeLimit
        let isOnPlane = { (plane: Plane, point: SIMD3<Double>) in
            abs(plane.height(of: point)) <= planeInlierThresholdMeters
        }

        // A fixed seed keeps results reproducible for the same depth data.
        var generator = SplitMix64(state: 0x4D61_6372_6F44_6570)
        var bestPlane: Plane?
        var bestCount = 0
        for _ in 0..<planeSearchTrials {
            guard ContinuousClock.now < deadline else {
                throw VolumeCalculationError.planeFitTimedOut
            }
            let candidate = plane(
                through: points[Int.random(in: points.indices, using: &generator)],
                points[Int.random(in: points.indices, using: &generator)],
                points[Int.random(in: points.indices, using: &generator)]
            )
            guard let candidate else { continue }
            let count = points.reduce(0) { $0 + (isOnPlane(candidate, $1) ? 1 : 0) }
            if count > bestCount {
                bestCount = count
                bestPlane = candidate
            }
        }

        guard let bestPlane, Double(bestCount) / Double(points.count) >= minimumPlaneInlierFraction else {
            throw VolumeCalculationError.noReferenceSurface
        }
        let inliers = points.filter { isOnPlane(bestPlane, $0) }
        guard let refined = leastSquaresPlane(through: inliers),
              acos(min(refined.normal.z, 1)) * 180 / .pi <= maximumPlaneTiltDegrees else {
            throw VolumeCalculationError.noReferenceSurface
        }
        return refined
    }

    private static func plane(through a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Plane? {
        let cross = simd_cross(b - a, c - a)
        let length = simd_length(cross)
        // Points that are nearly in line don't define a plane.
        guard length > 1e-8 else { return nil }
        let normal = (cross.z >= 0 ? cross : -cross) / length
        return Plane(normal: normal, offset: simd_dot(normal, a))
    }

    /// Solves z = ax + by + c. Depth noise runs along z, so that's the axis to minimize.
    private static func leastSquaresPlane(through points: [SIMD3<Double>]) -> Plane? {
        var normalMatrix = simd_double3x3()
        var right = SIMD3<Double>()
        for point in points {
            let row = SIMD3<Double>(point.x, point.y, 1)
            normalMatrix.columns.0 += row * row.x
            normalMatrix.columns.1 += row * row.y
            normalMatrix.columns.2 += row * row.z
            right += row * point.z
        }
        guard abs(normalMatrix.determinant) > 1e-12 else { return nil }
        let solution = normalMatrix.inverse * right

        let raw = SIMD3<Double>(-solution.x, -solution.y, 1)
        let length = simd_length(raw)
        let normal = raw / length
        var plane = Plane(normal: normal, offset: solution.z / length)
        let squaredError = points.reduce(0.0) { $0 + pow(plane.height(of: $1), 2) }
        plane.residual = (squaredError / Double(points.count)).squareRoot()
        return plane
    }

    // MARK: Footprint

    /// The largest 4-connected group of samples above the food height threshold.
    private static func largestConnectedFood(in samples: [Sample], plane: Plane) -> [Sample] {
        var unvisited: [SIMD2<Int>: Sample] = [:]
        for sample in samples where plane.height(of: sample.position) >= minimumFoodHeightMeters {
            unvisited[SIMD2(sample.column, sample.row)] = sample
        }

        var largest: [Sample] = []
        // Walking the samples, not the dictionary, keeps ties and results repeatable.
        for sample in samples where unvisited[SIMD2(sample.column, sample.row)] != nil {
            var component: [Sample] = []
            var stack = [SIMD2(sample.column, sample.row)]
            while let cell = stack.popLast() {
                guard let sample = unvisited.removeValue(forKey: cell) else { continue }
                component.append(sample)
                stack.append(cell &+ SIMD2(1, 0))
                stack.append(cell &- SIMD2(1, 0))
                stack.append(cell &+ SIMD2(0, 1))
                stack.append(cell &- SIMD2(0, 1))
            }
            if component.count > largest.count {
                largest = component
            }
        }
        return largest
    }

    /// The item's outline, projected onto the plane and measured there.
    ///
    /// Each image row contributes the outer edges of its first and last food pixels, at
    /// those pixels' depths. Joining them gives a polygon, whose area comes from the
    /// shoelace formula. Dropouts inside the item need no special handling, because only
    /// the edges matter. The cost is that a hollow or C-shaped item counts as filled.
    private static func footprint(
        of food: [Sample],
        on plane: Plane,
        camera: CameraIntrinsics
    ) -> (area: Double, width: Double, length: Double) {
        var edgesByRow: [Int: (first: Sample, last: Sample)] = [:]
        for sample in food {
            let current = edgesByRow[sample.row] ?? (sample, sample)
            edgesByRow[sample.row] = (
                sample.column < current.first.column ? sample : current.first,
                sample.column > current.last.column ? sample : current.last
            )
        }

        let imageRight = SIMD3<Double>(1, 0, 0)
        let across = simd_normalize(imageRight - plane.normal * simd_dot(plane.normal, imageRight))
        let along = simd_cross(plane.normal, across)
        func planePoint(column: Int, row: Int, depth: Double) -> SIMD2<Double> {
            let position = SIMD3<Double>(camera.unproject(column: Float(column), row: Float(row), depth: Float(depth)))
            return SIMD2(simd_dot(position, across), simd_dot(position, along))
        }

        let rows = edgesByRow.keys.sorted()
        var outline: [SIMD2<Double>] = []
        for row in rows {
            guard let left = edgesByRow[row]?.first else { continue }
            outline.append(planePoint(column: left.column, row: row, depth: left.position.z))
            outline.append(planePoint(column: left.column, row: row + 1, depth: left.position.z))
        }
        for row in rows.reversed() {
            guard let right = edgesByRow[row]?.last else { continue }
            outline.append(planePoint(column: right.column + 1, row: row + 1, depth: right.position.z))
            outline.append(planePoint(column: right.column + 1, row: row, depth: right.position.z))
        }

        var doubledArea = 0.0
        for index in outline.indices {
            let current = outline[index]
            let next = outline[(index + 1) % outline.count]
            doubledArea += current.x * next.y - next.x * current.y
        }
        let xs = outline.map(\.x)
        let ys = outline.map(\.y)
        return (
            abs(doubledArea) / 2,
            (xs.max() ?? 0) - (xs.min() ?? 0),
            (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    // MARK: Statistics

    private static func percentile(_ fraction: Double, of values: [Double]) -> Double {
        let sorted = values.sorted()
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    /// Combines the independent relative errors in a product: shape, footprint and height.
    /// The footprint term is half the boundary's pixels: for a disc of N pixels that's √(π/N).
    private static func relativeUncertainty(shape: FoodShape, sampleCount: Int, height: Double, planeResidual: Double) -> Double {
        let footprint = (Double.pi / Double(sampleCount)).squareRoot()
        let heightError = (depthNoiseMeters * depthNoiseMeters + planeResidual * planeResidual).squareRoot() / height
        return (pow(shape.relativeUncertainty, 2) + footprint * footprint + heightError * heightError).squareRoot()
    }
}

/// A small seedable generator, because the system generator can't be seeded.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
