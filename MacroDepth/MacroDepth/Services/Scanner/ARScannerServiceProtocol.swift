// Services/Scanner/ARScannerServiceProtocol.swift

import Foundation

/// Boundary between the UI and the AR/depth capture pipeline.
///
/// Implementations are actors (or otherwise `Sendable`). `capture()` must copy
/// all pixel data out of the underlying frame before returning, so no `ARFrame`
/// is ever retained across an `await`.
protocol ARScannerServiceProtocol: Sendable {
    var capabilities: ScannerCapabilities { get }

    /// A stream of state changes. Each call returns an independent stream that
    /// starts with the current state.
    func stateUpdates() -> AsyncStream<ScannerState>

    /// Starts the session. Idempotent; returns once the session is running.
    func start() async throws

    func stop() async

    /// Captures the current frame: downscaled JPEG, depth map (if available),
    /// intrinsics and camera pose.
    func capture() async throws -> DepthCapture

    /// Captures the optional angled photo as a downscaled JPEG. RGB only: the scan's
    /// single depth map always comes from `capture()`.
    func captureSecondaryImage() async throws -> Data
}
