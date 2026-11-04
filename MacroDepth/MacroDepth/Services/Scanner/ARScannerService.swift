// Services/Scanner/ARScannerService.swift

import ARKit
import Foundation

/// The real scanner: an `ARSession` with world tracking, plus LiDAR's smoothed scene
/// depth on devices that have it. On other devices `capture()` returns no depth and
/// analysis falls back to photo-only estimates.
///
/// Main-actor isolated because `session` is shared with the live `ARView` and delivers
/// its delegate callbacks on the main queue. Pixel conversion runs off the main actor.
@MainActor
final class ARScannerService: NSObject, ARScannerServiceProtocol {
    /// How long `capture()` waits for a usable frame, since smoothed depth needs a few
    /// frames to appear after the session starts.
    static let frameWaitTimeout: Duration = .seconds(2)

    nonisolated let capabilities: ScannerCapabilities
    let session = ARSession()

    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .idle)
    private var isRunning = false
    private var trackingQuality = ScannerState.TrackingQuality.notAvailable

    private var requiresDepth: Bool { capabilities.depthSource == .lidar }

    init(capabilities: ScannerCapabilities) {
        self.capabilities = capabilities
        super.init()
        session.delegate = self
    }

    static func makeConfiguration(for capabilities: ScannerCapabilities) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = capabilities.depthSource == .lidar ? [.smoothedSceneDepth] : []
        // Nothing is rendered into the scene, so skip work that only serves AR content.
        configuration.environmentTexturing = .none
        configuration.isLightEstimationEnabled = false
        return configuration
    }

    // MARK: ARScannerServiceProtocol

    nonisolated func stateUpdates() -> AsyncStream<ScannerState> {
        broadcaster.stream()
    }

    func start() async throws {
        if !isRunning {
            guard capabilities.supportsWorldTracking, ARWorldTrackingConfiguration.isSupported else {
                broadcaster.send(.failed(.worldTrackingUnsupported))
                throw ScannerError.worldTrackingUnsupported
            }
            trackingQuality = .notAvailable
            broadcaster.send(.starting)
            session.run(Self.makeConfiguration(for: capabilities), options: [.resetTracking, .removeExistingAnchors])
            isRunning = true
        }
        try await waitUntilRunning()
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        session.pause()
        broadcaster.send(.idle)
    }

    func capture() async throws -> DepthCapture {
        let snapshot = try await waitForFrame(requiringDepth: requiresDepth)
        return try await Task.detached(priority: .userInitiated) {
            try ARFrameConverter.makeCapture(from: snapshot)
        }.value
    }

    func captureSecondaryImage() async throws -> Data {
        // RGB only: the scan's depth map always comes from `capture()`.
        let snapshot = try await waitForFrame(requiringDepth: false)
        return try await Task.detached(priority: .userInitiated) {
            try ARFrameConverter.encodeUprightJPEG(snapshot.image).data
        }.value
    }

    // MARK: Private

    private func waitUntilRunning() async throws {
        for await state in broadcaster.stream() {
            switch state {
            case .running: return
            case .failed(let error): throw error
            case .idle: throw ScannerError.sessionNotRunning    // stopped while starting
            case .starting, .interrupted: continue              // resumes when the interruption ends
            }
        }
        // The stream only ends early because this task was cancelled.
        try Task.checkCancellation()
        throw ScannerError.sessionNotRunning
    }

    /// `frame` stays inside one synchronous loop iteration, so no `ARFrame` is ever
    /// retained across the `await`.
    private func waitForFrame(requiringDepth: Bool) async throws -> ARFrameSnapshot {
        let deadline = ContinuousClock.now + Self.frameWaitTimeout
        while true {
            guard isRunning else { throw ScannerError.sessionNotRunning }
            if broadcaster.latest == .interrupted { throw ScannerError.sessionInterrupted }

            if let frame = session.currentFrame, !requiringDepth || frame.smoothedSceneDepth != nil {
                return ARFrameSnapshot(
                    image: frame.capturedImage,
                    depth: requiringDepth ? frame.smoothedSceneDepth?.depthMap : nil,
                    confidence: requiringDepth ? frame.smoothedSceneDepth?.confidenceMap : nil,
                    intrinsics: frame.camera.intrinsics,
                    cameraTransform: frame.camera.transform
                )
            }

            guard ContinuousClock.now < deadline else { throw ScannerError.captureTimedOut }
            try await Task.sleep(for: .milliseconds(33))
        }
    }
}

// MARK: - ARSessionDelegate

/// Deliberately doesn't implement `session(_:didUpdate:)`: frames are read on demand
/// from `session.currentFrame`, so the delegate can never hold frames back.
extension ARScannerService: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard isRunning else { return }
        trackingQuality = ScannerState.TrackingQuality(camera.trackingState)
        if broadcaster.latest != .interrupted {
            broadcaster.send(.running(trackingQuality))
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard isRunning else { return }
        broadcaster.send(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard isRunning else { return }
        broadcaster.send(.running(trackingQuality))
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        isRunning = false
        broadcaster.send(.failed(ScannerError(sessionError: error)))
    }
}

// MARK: - ARKit mapping

extension ScannerState.TrackingQuality {
    init(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            self = .normal
        case .notAvailable:
            self = .notAvailable
        case .limited(let reason):
            self = .limited(reason: Self.message(for: reason))
        }
    }

    private static func message(for reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: "Starting tracking. Hold the phone steady."
        case .relocalizing: "Resuming tracking. Hold the phone steady."
        case .excessiveMotion: "Move the phone more slowly"
        case .insufficientFeatures: "Add more light or include more of the table"
        @unknown default: "Tracking is limited"
        }
    }
}

extension ScannerError {
    init(sessionError error: any Error) {
        switch (error as? ARError)?.code {
        case .cameraUnauthorized: self = .cameraPermissionDenied
        case .unsupportedConfiguration: self = .worldTrackingUnsupported
        default: self = .sessionFailed(reason: error.localizedDescription)
        }
    }
}
