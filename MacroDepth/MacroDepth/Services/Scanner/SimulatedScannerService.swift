// Services/Scanner/SimulatedScannerService.swift

import Foundation

/// Scanner backed by the synthetic sample scene. Used in the Simulator, in
/// SwiftUI Previews, and in tests. It never touches ARKit or the camera.
actor SimulatedScannerService: ARScannerServiceProtocol {
    nonisolated let capabilities: ScannerCapabilities

    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .idle)
    private let startupDelay: Duration
    private let captureDelay: Duration
    private let startFailure: ScannerError?
    private let captureFailure: ScannerError?
    private var isRunning = false

    init(
        capabilities: ScannerCapabilities = .simulated,
        startupDelay: Duration = .milliseconds(400),
        captureDelay: Duration = .milliseconds(250),
        startFailure: ScannerError? = nil,
        captureFailure: ScannerError? = nil
    ) {
        self.capabilities = capabilities
        self.startupDelay = startupDelay
        self.captureDelay = captureDelay
        self.startFailure = startFailure
        self.captureFailure = captureFailure
    }

    nonisolated func stateUpdates() -> AsyncStream<ScannerState> {
        broadcaster.stream()
    }

    func start() async throws {
        guard !isRunning else { return }
        broadcaster.send(.starting)
        do {
            try await Task.sleep(for: startupDelay)
        } catch {
            broadcaster.send(.idle)
            throw error
        }
        if let startFailure {
            broadcaster.send(.failed(startFailure))
            throw startFailure
        }
        isRunning = true
        broadcaster.send(.running(.normal))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        broadcaster.send(.idle)
    }

    func capture() async throws -> DepthCapture {
        guard isRunning else { throw ScannerError.sessionNotRunning }
        try await Task.sleep(for: captureDelay)
        // Actor reentrancy: the session may have been stopped while we slept.
        guard isRunning else { throw ScannerError.sessionNotRunning }
        if let captureFailure { throw captureFailure }
        return try SampleScene.makeCapture(includeDepth: capabilities.canMeasureVolume)
    }

    func captureSecondaryImage() async throws -> Data {
        guard isRunning else { throw ScannerError.sessionNotRunning }
        try await Task.sleep(for: captureDelay)
        guard isRunning else { throw ScannerError.sessionNotRunning }
        if let captureFailure { throw captureFailure }
        return try SampleScene.renderJPEG()
    }
}
