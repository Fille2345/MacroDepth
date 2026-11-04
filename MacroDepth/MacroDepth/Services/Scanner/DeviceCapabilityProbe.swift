// Services/Scanner/DeviceCapabilityProbe.swift

import ARKit
import Foundation

/// Detects what the current hardware supports. Safe to call on the Simulator.
enum DeviceCapabilityProbe {
    static func currentHardware() -> ScannerCapabilities {
        #if targetEnvironment(simulator)
        return .simulated
        #else
        guard ARWorldTrackingConfiguration.isSupported else { return .unsupported }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            return .lidar
        }
        return .cameraOnly
        #endif
    }
}
