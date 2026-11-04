// Domain/Scanner/ScannerCapabilities.swift

import Foundation

/// What a scanner implementation (or the device hardware) can do.
struct ScannerCapabilities: Sendable, Equatable {
    enum DepthSource: String, Sendable {
        case lidar
        /// Synthetic depth from the bundled sample scene (Simulator, Previews).
        case simulated
        case none
    }

    let depthSource: DepthSource
    let supportsWorldTracking: Bool
    let requiresCameraAccess: Bool

    static let lidar = ScannerCapabilities(depthSource: .lidar, supportsWorldTracking: true, requiresCameraAccess: true)
    static let cameraOnly = ScannerCapabilities(depthSource: .none, supportsWorldTracking: true, requiresCameraAccess: true)
    static let unsupported = ScannerCapabilities(depthSource: .none, supportsWorldTracking: false, requiresCameraAccess: true)
    static let simulated = ScannerCapabilities(depthSource: .simulated, supportsWorldTracking: false, requiresCameraAccess: false)
    static let simulatedWithoutDepth = ScannerCapabilities(depthSource: .none, supportsWorldTracking: false, requiresCameraAccess: false)

    var canMeasureVolume: Bool { depthSource != .none }

    var summary: String {
        switch depthSource {
        case .lidar: "LiDAR depth"
        case .simulated: "Simulated depth"
        case .none: requiresCameraAccess ? "Photo only" : "Simulated photo only"
        }
    }

    var systemImage: String {
        switch depthSource {
        case .lidar: "cube.transparent"
        case .simulated: "cube.transparent.fill"
        case .none: "camera"
        }
    }
}
