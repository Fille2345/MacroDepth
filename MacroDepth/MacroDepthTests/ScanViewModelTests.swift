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
    private(set) var estimationQueries: [NutritionQuery] = []

    private let mock = MockNutritionService(latency: .zero)

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        detectionImages.append(images)
        detectionNotes.append(userNotes)
        return try await mock.detectFoodItems(in: images, userNotes: userNotes)
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        estimationImages.append(images)
        estimationNotes.append(userNotes)
        estimationQueries.append(contentsOf: queries)
        return try await mock.estimateNutrition(for: queries, images: images, userNotes: userNotes)
    }
}

/// Loses the first item's estimate, as when the model's values fail validation.
private struct PartialNutritionService: NutritionServiceProtocol {
    private let mock = MockNutritionService(latency: .zero)

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        try await mock.detectFoodItems(in: images, userNotes: userNotes)
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        Array(try await mock.estimateNutrition(for: queries, images: images, userNotes: userNotes).dropFirst())
    }
}

/// Measures with the real service, except for boxes it's told to fail.
private final class StubVolumeCalculator: VolumeCalculatorServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let failingBoxes: Set<NormalizedBoundingBox>
    private let failure: VolumeCalculationError
    private var recordedShapes: [NormalizedBoundingBox: FoodShape] = [:]

    init(failingBoxes: Set<NormalizedBoundingBox>, failure: VolumeCalculationError = .insufficientDepthData) {
        self.failingBoxes = failingBoxes
        self.failure = failure
    }

    var shapes: [NormalizedBoundingBox: FoodShape] { lock.withLock { recordedShapes } }

    func estimateVolume(
        in box: NormalizedBoundingBox,
        shape: FoodShape,
        depthMap: DepthMap,
        intrinsics: CameraIntrinsics
    ) throws -> FoodVolumeEstimate {
        lock.withLock { recordedShapes[box] = shape }
        if failingBoxes.contains(box) { throw failure }
        return try VolumeCalculatorService().estimateVolume(in: box, shape: shape, depthMap: depthMap, intrinsics: intrinsics)
    }
}

/// Serves a capture with no depth, or depth without intrinsics.
private struct NoDepthScanner: ARScannerServiceProtocol {
    var keepsDepthMap = false
    let capabilities = ScannerCapabilities.simulated
    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .running(.normal))

    func stateUpdates() -> AsyncStream<ScannerState> { broadcaster.stream() }
    func start() async throws {}
    func stop() async {}
    func captureSecondaryImage() async throws -> Data { StubScanner.secondaryImage }

    func capture() async throws -> DepthCapture {
        let sample = try SampleScene.makeCapture(includeDepth: keepsDepthMap)
        return DepthCapture(
            imageJPEGData: sample.imageJPEGData,
            imagePixelSize: sample.imagePixelSize,
            depthMap: sample.depthMap,
            intrinsics: nil,
            cameraPose: nil
        )
    }
}

/// Every box sees near and far depth at once, like food held over a floor.
private struct HandHeldScanner: ARScannerServiceProtocol {
    let capabilities = ScannerCapabilities.simulated
    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .running(.normal))

    func stateUpdates() -> AsyncStream<ScannerState> { broadcaster.stream() }
    func start() async throws {}
    func stop() async {}
    func captureSecondaryImage() async throws -> Data { StubScanner.secondaryImage }

    func capture() async throws -> DepthCapture {
        let sample = try SampleScene.makeCapture(includeDepth: false)
        let width = SampleScene.depthWidth
        let height = SampleScene.depthHeight
        var depths = [Float](repeating: 1.57, count: width * height)
        for row in 0..<height {
            for column in 0..<width where (column / 12 + row / 12).isMultiple(of: 2) {
                depths[row * width + column] = 0.2
            }
        }
        return DepthCapture(
            imageJPEGData: sample.imageJPEGData,
            imagePixelSize: sample.imagePixelSize,
            depthMap: DepthMap(width: width, height: height, depthMeters: depths),
            intrinsics: sample.intrinsics,
            cameraPose: sample.cameraPose
        )
    }
}

/// Records whether measuring happens away from the main thread.
private final class ThreadRecordingCalculator: VolumeCalculatorServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var ranOnMainThread = false

    var didRunOnMainThread: Bool { lock.withLock { ranOnMainThread } }

    func estimateVolume(in box: NormalizedBoundingBox, shape: FoodShape, depthMap: DepthMap, intrinsics: CameraIntrinsics) throws -> FoodVolumeEstimate {
        let isMain = Thread.isMainThread
        lock.withLock { ranOnMainThread = ranOnMainThread || isMain }
        return try VolumeCalculatorService().estimateVolume(in: box, shape: shape, depthMap: depthMap, intrinsics: intrinsics)
    }
}

@MainActor
struct ScanViewModelTests {
    @Test func foodHeldOverAFloorFallsBackToPhotoEstimates() async throws {
        let spy = SpyNutritionService()
        let viewModel = makeViewModel(
            scanner: HandHeldScanner(),
            nutrition: spy,
            persistence: try SwiftDataPersistenceService.makeInMemory()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        #expect(await spy.estimationQueries.allSatisfy { $0.measuredVolume == nil })
        #expect(!viewModel.drafts.isEmpty)
        #expect(viewModel.drafts.allSatisfy { $0.portion.source == .visualEstimate && $0.measuredSize == nil })
        #expect(viewModel.drafts.allSatisfy { $0.portion.grams < 1_000 })
    }

    @Test func measuringStaysOffTheMainThread() async throws {
        let calculator = ThreadRecordingCalculator()
        let viewModel = makeViewModel(
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory(),
            volumeCalculator: calculator
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        #expect(!calculator.didRunOnMainThread)
    }

    private func runToReview(_ viewModel: ScanViewModel) async throws {
        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.analyze()
        try await waitForPhase(.review, in: viewModel)
    }

    @Test func measuredVolumesReachGeminiAndDriveTheGrams() async throws {
        let spy = SpyNutritionService()
        let viewModel = makeViewModel(nutrition: spy, persistence: try SwiftDataPersistenceService.makeInMemory())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        let queries = await spy.estimationQueries
        #expect(queries.count == SampleScene.foods.count)
        #expect(queries.allSatisfy { $0.measuredVolume?.method == .shapeHeuristic })

        #expect(viewModel.drafts.count == SampleScene.foods.count)
        #expect(!viewModel.hasPhotoOnlyEstimates)
        for draft in viewModel.drafts {
            let size = try #require(draft.measuredSize)
            let density = try #require(draft.portion.densityGramsPerCubicCentimeter)
            #expect(draft.portion.source == .lidarVolume)
            #expect(draft.portion.volume == size.measurement)
            #expect(size.widthCentimeters > 0 && size.lengthCentimeters > 0 && size.heightCentimeters > 0)
            #expect(abs(draft.portion.grams - size.measurement.cubicCentimeters * density) < 1e-9)
        }
    }

    @Test func eachItemUsesItsCategorysShape() async throws {
        let calculator = StubVolumeCalculator(failingBoxes: [])
        let viewModel = makeViewModel(
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory(),
            volumeCalculator: calculator
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        for food in SampleScene.foods {
            #expect(calculator.shapes[SampleScene.boundingBox(for: food)] == FoodShape(category: food.category))
        }
        let chicken = try #require(viewModel.drafts.first { $0.category == .meat })
        #expect(chicken.measuredSize?.shape == .slab)
    }

    @Test(arguments: [VolumeCalculationError.insufficientDepthData, .invalidIntrinsics, .noReferenceSurface, .planeFitTimedOut, .noFoodAboveSurface])
    func oneUnmeasurableItemFallsBackAloneToAPhotoEstimate(failure: VolumeCalculationError) async throws {
        let failing = try #require(SampleScene.foods.first)
        let spy = SpyNutritionService()
        let calculator = StubVolumeCalculator(failingBoxes: [SampleScene.boundingBox(for: failing)], failure: failure)
        let viewModel = makeViewModel(nutrition: spy, persistence: try SwiftDataPersistenceService.makeInMemory(), volumeCalculator: calculator)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        let queries = await spy.estimationQueries
        #expect(queries.first { $0.label == failing.label }?.measuredVolume == nil)
        #expect(queries.filter { $0.measuredVolume != nil }.count == SampleScene.foods.count - 1)

        #expect(viewModel.drafts.count == SampleScene.foods.count)
        #expect(viewModel.hasPhotoOnlyEstimates)
        #expect(!viewModel.hasUnestimatedItems)
        for draft in viewModel.drafts {
            let isFailing = draft.name == failing.label
            #expect(draft.portion.source == (isFailing ? .visualEstimate : .lidarVolume))
            #expect((draft.measuredSize == nil) == isFailing)
        }
        let photoEstimate = try #require(viewModel.drafts.first { $0.name == failing.label })
        #expect(photoEstimate.portion.grams == failing.visualEstimateGrams)
    }

    @Test(arguments: [false, true])
    func captureWithoutUsableDepthUsesPhotoEstimatesThroughout(keepsDepthMap: Bool) async throws {
        let calculator = StubVolumeCalculator(failingBoxes: [])
        let viewModel = makeViewModel(
            scanner: NoDepthScanner(keepsDepthMap: keepsDepthMap),
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory(),
            volumeCalculator: calculator
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        #expect(calculator.shapes.isEmpty)
        #expect(!viewModel.drafts.isEmpty)
        #expect(viewModel.drafts.allSatisfy { $0.portion.source == .visualEstimate && $0.measuredSize == nil })
    }

    @Test func editingTheWeightKeepsTheMeasurementVisible() async throws {
        let viewModel = makeViewModel(nutrition: MockNutritionService(latency: .zero), persistence: try SwiftDataPersistenceService.makeInMemory())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)

        let draft = try #require(viewModel.drafts.first)
        viewModel.stepGrams(for: draft.id, by: ScanViewModel.gramStep)
        let edited = try #require(viewModel.drafts.first { $0.id == draft.id })
        #expect(edited.portion.source == .userAdjusted)
        #expect(edited.measuredSize == draft.measuredSize)
    }

    @Test func flagsAnItemWithoutAnEstimate() async throws {
        let viewModel = makeViewModel(nutrition: PartialNutritionService(), persistence: try SwiftDataPersistenceService.makeInMemory())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.analyze()
        try await waitForPhase(.review, in: viewModel)

        #expect(viewModel.hasUnestimatedItems)
        #expect(!viewModel.usesSampleAnalysis)
    }

    @Test func noWarningWhenEveryItemHasAnEstimateAndMockIsLabelled() async throws {
        let viewModel = makeViewModel(nutrition: MockNutritionService(latency: .zero), persistence: try SwiftDataPersistenceService.makeInMemory())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        try await waitForPhase(.ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await waitForPhase(.awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.analyze()
        try await waitForPhase(.review, in: viewModel)

        #expect(!viewModel.hasUnestimatedItems)
        #expect(viewModel.usesSampleAnalysis)

        let draft = try #require(viewModel.drafts.first)
        viewModel.removeDraft(id: draft.id)
        #expect(!viewModel.hasUnestimatedItems)   // removing an item yourself isn't a missing estimate
    }

    private func makeViewModel(
        scanner: any ARScannerServiceProtocol = StubScanner(),
        nutrition: any NutritionServiceProtocol,
        persistence: any PersistenceServiceProtocol,
        volumeCalculator: any VolumeCalculatorServiceProtocol = VolumeCalculatorService()
    ) -> ScanViewModel {
        ScanViewModel(
            scanner: scanner,
            nutrition: nutrition,
            persistence: persistence,
            permissions: MockCameraPermissionService(),
            volumeCalculator: volumeCalculator
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
