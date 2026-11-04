// Domain/Measurement/VolumeMeasurement.swift

import Foundation

/// Volume of one food item measured from depth data.
struct VolumeMeasurement: Sendable, Hashable {
    enum Method: String, Sendable, Codable {
        /// Measured footprint and height above a fitted plane, applied to a simple solid.
        case shapeHeuristic
        /// Single smoothed depth frame integrated as a height field above a fitted plane.
        case singleFrameHeightField
        /// Several frames fused into a point cloud (planned extension).
        case multiFrameFusion
    }

    let cubicCentimeters: Double
    /// One-sigma uncertainty, same unit as `cubicCentimeters`.
    let uncertaintyCubicCentimeters: Double
    /// Number of depth samples that contributed to the integral.
    let sampleCount: Int
    let method: Method

    init?(
        cubicCentimeters: Double,
        uncertaintyCubicCentimeters: Double = 0,
        sampleCount: Int,
        method: Method
    ) {
        guard cubicCentimeters.isFinite, cubicCentimeters >= 0,
              uncertaintyCubicCentimeters.isFinite, uncertaintyCubicCentimeters >= 0,
              sampleCount >= 0 else { return nil }
        self.cubicCentimeters = cubicCentimeters
        self.uncertaintyCubicCentimeters = uncertaintyCubicCentimeters
        self.sampleCount = sampleCount
        self.method = method
    }

    /// Uncertainty relative to the measured volume; 1 when the volume is zero.
    var relativeUncertainty: Double {
        cubicCentimeters > 0 ? uncertaintyCubicCentimeters / cubicCentimeters : 1
    }
}
