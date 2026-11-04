// Domain/Errors/VolumeCalculationError.swift

import Foundation

/// Why an item's volume couldn't be measured. None of these is fatal: the item
/// falls back to a photo estimate.
enum VolumeCalculationError: Error, Equatable, Sendable {
    /// Too few usable depth samples inside the bounding box.
    case insufficientDepthData
    /// The intrinsics can't be mapped onto the depth map.
    case invalidIntrinsics
    /// No plate or table could be found around the bounding box.
    case noReferenceSurface
    /// Nothing inside the box rises far enough above the surface to measure.
    case noFoodAboveSurface
}
