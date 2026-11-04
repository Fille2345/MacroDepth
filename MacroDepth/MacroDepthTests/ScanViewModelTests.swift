// MacroDepthTests/ScanViewModelTests.swift

import Foundation
import Testing
@testable import MacroDepth

/// Serves fixed images so tests can check exactly what reaches the nutrition service.
private struct StubScanner: ARScannerServiceProtocol {
    static let secondaryImage = Data([0xFF, 0xD8, 0x02])

    let capabilities = ScannerCapabilities.simulated
    var secondaryFailure: ScannerError?
    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .running(.normal))

    init(secondaryFailure: ScannerError? = nil) {
        self.secondaryFailure = secondaryFailure
    }

    func stateUpdates() -> AsyncStream<ScannerState> { broadcaster.stream() }
    func start() async throws {}
    func stop() async {}

    func capture() async throws -> DepthCapture {
        try SampleScene.makeCapture(includeDepth: true)
    }

    func captureSecondaryImage() async throws -> Data {
        if let secondaryFailure { throw secondaryFailure }
        return Self.secondaryImage
    }
}

/// Records service calls, then delegates to the mock for results.
private actor SpyNutritionService: NutritionServiceProtocol {
    private(set) var detectionImages: [[Data]] = []
    private(set) var detectionNotes: [String?] = []
    private(set) var estimationImages: [[Data]] = []
    private(set) var estimationNotes: [String?] = []

    private let mock = MockNutritionService(latency: .zero)

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        detectionImages.append(images)
        detectionNotes.append(userNotes)
        return try await mock.detectFoodItems(in: images, userNotes: userNotes)
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        estimationImages.append(images)
        estimationNotes.append(userNotes)
        return try await mock.estimateNutrition(for: queries, images: images, userNotes: userNotes)
    }
}

@MainActor
struct ScanViewModelTests {
    private func makeViewModel(
        scanner: any ARScannerServiceProtocol = StubScanner(),
        nutrition: any NutritionServiceProtocol,
        persistence: any PersistenceServiceProtocol
    ) -> ScanViewModel {
        ScanViewModel(
            scanner: scanner,
            nutrition: nutrition,
            persistence: persistence,
            permissions: MockCameraPermissionService()
        )
    }

    private func waitForPhase(_ phase: ScanViewModel.Phase, in viewModel: ScanViewModel) async throws {
        for _ in 0..<1_000 {
            if viewModel.phase == phase { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for \(phase); phase is \(viewModel.phase)")
        throw CancellationError()
    }

    @Test func skippingTheAngledPhotoSubmitsOneImage() async throws {
        let spy = SpyNutritionService()
        let viewModel = makeViewModel(nutrition: spy, persistence: try SwiftDataPersistenceService.makeInMemory())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        #expect(await spy.detectionImages.isEmpty)   // nothing is submitted until the user confirms

        viewModel.skipSecondaryPhoto()
        #expect(viewModel.phase == .readyToAnalyze)
        viewModel.analyze()
        try await waitForPhase(.review, in: viewModel)

        #expect(await spy.detectionImages.first?.count == 1)
        #expect(await spy.detectionNotes == [nil])
        #expect(await spy.estimationNotes == [nil])
    }

    @Test func bothPhotosAndNotesReachTheServiceAndNotesAreSaved() async throws {
        let spy = SpyNutritionService()
        let persistence = try SwiftDataPersistenceService.makeInMemory()
        let viewModel = makeViewModel(nutrition: spy, persistence: persistence)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        let primaryImage = try #require(viewModel.capture?.imageJPEGData)

        viewModel.captureSecondaryPhoto()
        try await waitForPhase(.readyToAnalyze, in: viewModel)
        viewModel.userNotes = "  Fried in butter\n"
        viewModel.analyze()
        try await waitForPhase(.review, in: viewModel)

        // The top-down photo must stay first: boxes and depth refer to it.
        #expect(await spy.detectionImages == [[primaryImage, StubScanner.secondaryImage]])
        #expect(await spy.estimationImages == [[primaryImage, StubScanner.secondaryImage]])
        #expect(await spy.detectionNotes == ["Fried in butter"])
        #expect(await spy.estimationNotes == ["Fried in butter"])

        await viewModel.saveMeal()
        #expect(viewModel.phase == .saved)
        let meals = try persistence.meals(on: .now)
        #expect(meals.first?.notes == "Fried in butter")
    }

    @Test func angledPhotoFailureKeepsTheFirstPhotoAndCanBeSkipped() async throws {
        let viewModel = makeViewModel(
            scanner: StubScanner(secondaryFailure: .frameUnavailable),
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)

        viewModel.captureSecondaryPhoto()
        for _ in 0..<1_000 where viewModel.secondaryCaptureError == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.secondaryCaptureError != nil)
        #expect(viewModel.phase == .awaitingSecondaryPhoto)
        #expect(viewModel.capture != nil)
        #expect(viewModel.capture?.secondaryImageJPEGData == nil)

        viewModel.skipSecondaryPhoto()
        #expect(viewModel.phase == .readyToAnalyze)
        #expect(viewModel.secondaryCaptureError == nil)
    }

    @Test func retryAfterAnalysisFailureKeepsPhotosAndNotes() async throws {
        let viewModel = makeViewModel(
            nutrition: MockNutritionService(behavior: .failure(.offline), latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.userNotes = "Olive oil"
        viewModel.analyze()
        try await waitForPhase(.failed(ErrorPresentation(NutritionServiceError.offline)), in: viewModel)

        viewModel.retry()

        #expect(viewModel.phase == .readyToAnalyze)
        #expect(viewModel.capture != nil)
        #expect(viewModel.userNotes == "Olive oil")
    }

    @Test func resetClearsPhotosAndNotes() async throws {
        let viewModel = makeViewModel(
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        viewModel.captureSecondaryPhoto()
        try await waitForPhase(.readyToAnalyze, in: viewModel)
        viewModel.userNotes = "Olive oil"

        viewModel.reset()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.capture == nil)
        #expect(viewModel.secondaryPreviewImage == nil)
        #expect(viewModel.userNotes.isEmpty)
    }
}
