// MacroDepthTests/ManualTrackingTests.swift

import Foundation
import Testing
@testable import MacroDepth

struct FoodBarcodeTests {
    @Test(arguments: ["4006381333931", "96385074", "036000291452", " 4006381333931 ", "400-6381333931"])
    func acceptsValidCodes(code: String) {
        #expect(FoodBarcode.normalized(code) == code.filter { $0.isNumber })
    }

    @Test(arguments: ["", "abc", "123", "4006381333932", "96385075", "400638133393a", "٤٠٠٦٣٨١٣٣٣٩٣١"])
    func rejectsInvalidCodes(code: String) {
        #expect(FoodBarcode.normalized(code) == nil)
    }
}

struct MockFoodLookupServiceTests {
    private let service = MockFoodLookupService(latency: .zero)

    @Test func searchMatchesAnyCaseAndEveryWord() async throws {
        #expect(try await service.searchFoods(matching: "CHICKEN").map(\.name) == ["Chicken breast, cooked"])
        #expect(try await service.searchFoods(matching: "rice white").map(\.name) == ["White rice, cooked"])
        #expect(try await service.searchFoods(matching: "zzz").isEmpty)
        #expect(try await service.searchFoods(matching: "  ").isEmpty)
    }

    @Test func namesStartingWithTheQueryComeFirst() async throws {
        let results = try await service.searchFoods(matching: "m")
        #expect(results.first?.name.lowercased().hasPrefix("m") == true)
    }

    @Test func barcodeReturnsASampleOrNotFound() async throws {
        let product = try await service.product(forBarcode: "4006381333931")
        #expect(product?.barcode == "4006381333931")
        #expect(product?.name.contains("Sample") == true)
        #expect(try await service.product(forBarcode: MockFoodLookupService.unknownBarcode) == nil)
    }

    @Test func catalogValuesAreValid() {
        for food in MockFoodLookupService.catalog {
            #expect(food.macrosPer100Grams.isValid, "\(food.name)")
            #expect(food.macrosPer100Grams.macronutrientMassGrams <= GeminiNutritionPayload.maximumMacroMassPer100Grams, "\(food.name)")
            #expect(PortionCalculator.manualEntryRange.contains(food.typicalServingGrams), "\(food.name)")
        }
        #expect(Set(MockFoodLookupService.catalog.map(\.id)).count == MockFoodLookupService.catalog.count)
    }
}

/// A lookup whose searches can finish out of order.
private struct DelayedLookup: FoodLookupServiceProtocol {
    let delays: [String: Duration]

    func product(forBarcode barcode: String) async throws -> FoodProduct? { nil }

    func searchFoods(matching query: String) async throws -> [FoodProduct] {
        try await Task.sleep(for: delays[query] ?? .zero)
        return try await MockFoodLookupService(latency: .zero).searchFoods(matching: query)
    }
}

@MainActor
struct ManualTrackingViewModelTests {
    private func make(
        mode: ManualTrackingViewModel.Mode = .search,
        lookup: any FoodLookupServiceProtocol = MockFoodLookupService(latency: .zero),
        permissions: any CameraPermissionProviding = MockCameraPermissionService(),
        cameraExists: Bool = true,
        prepareCameraHandover: @escaping @MainActor () async -> Void = {}
    ) -> ManualTrackingViewModel {
        ManualTrackingViewModel(
            mode: mode,
            lookup: lookup,
            permissions: permissions,
            cameraExists: cameraExists,
            prepareCameraHandover: prepareCameraHandover
        )
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    // MARK: Search

    /// Counts searches, because Open Food Facts blocks clients that search too often.
    private final class CountingLookup: FoodLookupServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        var queries: [String] { lock.withLock { recorded } }

        func product(forBarcode barcode: String) async throws -> FoodProduct? { nil }

        func searchFoods(matching query: String) async throws -> [FoodProduct] {
            lock.withLock { recorded.append(query) }
            return try await MockFoodLookupService(latency: .zero).searchFoods(matching: query)
        }
    }

    @Test func typingNeverSearchesUntilSubmitted() async throws {
        let lookup = CountingLookup()
        let viewModel = make(lookup: lookup)
        for text in ["b", "ba", "ban", "bana", "banan", "banana"] {
            viewModel.searchText = text
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(lookup.queries.isEmpty)
        #expect(viewModel.searchedQuery == nil)

        viewModel.submitSearch()
        try await wait { !viewModel.isSearching }
        #expect(lookup.queries == ["banana"])
        #expect(viewModel.searchedQuery == "banana")
        #expect(viewModel.searchResults.map(\.name) == ["Banana"])
    }

    @Test func resubmittingTheSameQueryDoesNotSpendARequest() async throws {
        let lookup = CountingLookup()
        let viewModel = make(lookup: lookup)
        viewModel.searchText = "banana"
        viewModel.submitSearch()
        try await wait { !viewModel.isSearching }

        viewModel.searchText = " banana "
        viewModel.submitSearch()
        try await Task.sleep(for: .milliseconds(30))
        #expect(lookup.queries == ["banana"])
    }

    @Test func blankSubmitDoesNothing() async throws {
        let lookup = CountingLookup()
        let viewModel = make(lookup: lookup)
        viewModel.searchText = "   "
        viewModel.submitSearch()
        try await Task.sleep(for: .milliseconds(30))
        #expect(lookup.queries.isEmpty)
        #expect(!viewModel.isSearching)
    }

    @Test func editingKeepsResultsUntilTheNextSearchAndClearingRemovesThem() async throws {
        let viewModel = make()
        viewModel.searchText = "banana"
        viewModel.submitSearch()
        try await wait { !viewModel.searchResults.isEmpty }

        viewModel.searchText = "banan"
        #expect(viewModel.searchResults.map(\.name) == ["Banana"])

        viewModel.searchText = "  "
        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.searchedQuery == nil)
        #expect(!viewModel.isSearching)
    }

    @Test func noMatchesIsAnAnswerNotAnError() async throws {
        let viewModel = make()
        viewModel.searchText = "zzzz"
        viewModel.submitSearch()
        try await wait { !viewModel.isSearching }
        #expect(viewModel.searchedQuery == "zzzz")
        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.searchError == nil)
    }

    @Test func aSlowEarlierSearchCannotReplaceANewerOne() async throws {
        let viewModel = make(lookup: DelayedLookup(delays: ["apple": .milliseconds(150)]))
        viewModel.searchText = "apple"
        viewModel.submitSearch()
        try await Task.sleep(for: .milliseconds(20))
        viewModel.searchText = "banana"
        viewModel.submitSearch()
        try await wait { viewModel.searchResults.map(\.name) == ["Banana"] }
        try await Task.sleep(for: .milliseconds(200))
        #expect(viewModel.searchResults.map(\.name) == ["Banana"])
        #expect(!viewModel.isSearching)
    }

    @Test func searchFailureShowsAnErrorAndCanRetry() async throws {
        let failing = make(lookup: MockFoodLookupService(behavior: .failure(.offline), latency: .zero))
        failing.searchText = "banana"
        failing.submitSearch()
        try await wait { !failing.isSearching }
        #expect(failing.searchError != nil)
        #expect(failing.searchResults.isEmpty)

        // The same query can be resubmitted after a failure.
        failing.submitSearch()
        #expect(failing.isSearching)
    }

    // MARK: Barcode

    @Test func foundBarcodeOpensTheWeightStep() async {
        let viewModel = make(mode: .barcode)
        await viewModel.lookUpBarcode("4006381333931")
        #expect(viewModel.selectedProduct?.barcode == "4006381333931")
        #expect(viewModel.gramsText == "50")
        #expect(viewModel.lookupState == .idle)
    }

    @Test func unknownBarcodeReportsNotFound() async {
        let viewModel = make(mode: .barcode)
        await viewModel.lookUpBarcode(MockFoodLookupService.unknownBarcode)
        #expect(viewModel.lookupState == .notFound(MockFoodLookupService.unknownBarcode))
        #expect(viewModel.selectedProduct == nil)

        viewModel.switchMode(to: .search)
        #expect(viewModel.mode == .search)
        #expect(viewModel.lookupState == .idle)
    }

    @Test func invalidTypedCodeIsRejectedWithoutALookup() async {
        let viewModel = make(mode: .barcode)
        await viewModel.lookUpBarcode("12345")
        #expect(viewModel.lookupState == .invalidCode)
        await viewModel.lookUpBarcode("4006381333931")
        #expect(viewModel.selectedProduct != nil)
    }

    @Test func lookupFailureIsShownAndCanBeRetried() async {
        let viewModel = make(mode: .barcode, lookup: MockFoodLookupService(behavior: .failure(.serviceUnavailable), latency: .zero))
        await viewModel.lookUpBarcode("4006381333931")
        guard case .failed = viewModel.lookupState else {
            Issue.record("Expected failed, got \(viewModel.lookupState)")
            return
        }
        viewModel.resetLookup()
        #expect(viewModel.lookupState == .idle)
    }

    /// The camera reports the same code many times a second.
    @Test func repeatDetectionsOnlyLookUpOnce() async {
        let viewModel = make(mode: .barcode, lookup: MockFoodLookupService(latency: .milliseconds(30)))
        async let first: Void = viewModel.lookUpBarcode("4006381333931")
        async let second: Void = viewModel.lookUpBarcode("96385074")
        _ = await (first, second)
        #expect(viewModel.selectedProduct?.barcode == "4006381333931")
    }

    @Test func cameraStopsScanningOnceThereIsAResult() async {
        let viewModel = make(mode: .barcode)
        await viewModel.prepareCamera()
        #expect(viewModel.isCameraScanning)
        await viewModel.lookUpBarcode("4006381333931")
        #expect(!viewModel.isCameraScanning)
        viewModel.selectedProduct = nil
        #expect(viewModel.isCameraScanning)
    }

    @Test func cameraWaitsForTheHandoverThenChecksPermission() async {
        var handedOver = false
        let viewModel = make(mode: .barcode, prepareCameraHandover: { handedOver = true })
        await viewModel.prepareCamera()
        #expect(handedOver)
        #expect(viewModel.cameraState == .ready)
    }

    @Test func noCameraOrNoPermissionStillLeavesTyping() async {
        var handedOver = false
        let simulator = make(mode: .barcode, cameraExists: false, prepareCameraHandover: { handedOver = true })
        await simulator.prepareCamera()
        #expect(simulator.cameraState == .unavailable)
        #expect(!handedOver)   // the AR session keeps the camera it didn't need to give up

        let denied = make(mode: .barcode, permissions: MockCameraPermissionService(status: .denied))
        await denied.prepareCamera()
        #expect(denied.cameraState == .denied)
        await denied.lookUpBarcode("4006381333931")
        #expect(denied.selectedProduct != nil)
    }

    // MARK: Weight

    @Test func macrosFollowTheTypedWeight() async throws {
        let viewModel = make()
        let banana = try #require(MockFoodLookupService.catalog.first { $0.name == "Banana" })
        viewModel.selectedProduct = banana
        #expect(viewModel.gramsText == "120")
        #expect(abs((try #require(viewModel.entryMacros)).energyKilocalories - 108) < 1e-9)

        viewModel.gramsText = "200,5"
        #expect(viewModel.parsedGrams == 200.5)
        #expect(abs((try #require(viewModel.entryMacros)).energyKilocalories - 180.45) < 1e-9)
    }

    @Test(arguments: ["0", "0.5", "3001", "abc", "-5"])
    func unusableWeightMakesNoDraft(text: String) throws {
        let viewModel = make()
        viewModel.selectedProduct = MockFoodLookupService.catalog.first
        viewModel.gramsText = text
        #expect(viewModel.makeDraft() == nil)
        #expect(viewModel.gramsError != nil)
    }

    @Test func draftCarriesTheFoodAndChosenWeight() throws {
        let viewModel = make()
        let banana = try #require(MockFoodLookupService.catalog.first { $0.name == "Banana" })
        viewModel.selectedProduct = banana
        viewModel.gramsText = "150"

        let draft = try #require(viewModel.makeDraft())
        #expect(draft.name == "Banana")
        #expect(draft.category == .fruit)
        #expect(draft.portion.grams == 150)
        #expect(draft.portion.source == .manualEntry)
        #expect(draft.macrosPer100Grams == banana.macrosPer100Grams)
        #expect(draft.measuredSize == nil)
    }
}

/// Loses the first item's estimate, as when the model's values fail validation.
private struct LosesOneEstimate: NutritionServiceProtocol {
    private let mock = MockNutritionService(latency: .zero)

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        try await mock.detectFoodItems(in: images, userNotes: userNotes)
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        Array(try await mock.estimateNutrition(for: queries, images: images, userNotes: userNotes).dropFirst())
    }
}

/// Records calls, so the camera handover can be checked.
private final class RecordingScanner: ARScannerServiceProtocol, @unchecked Sendable {
    let capabilities = ScannerCapabilities.lidar
    private let lock = NSLock()
    private var recorded: [String] = []
    private let broadcaster = AsyncBroadcaster<ScannerState>(initialValue: .idle)
    var startError: ScannerError?

    var calls: [String] { lock.withLock { recorded } }

    func stateUpdates() -> AsyncStream<ScannerState> { broadcaster.stream() }

    func start() async throws {
        lock.withLock { recorded.append("start") }
        if let startError { throw startError }
        broadcaster.send(.running(.normal))
    }

    func stop() async {
        lock.withLock { recorded.append("stop") }
        broadcaster.send(.idle)
    }

    func capture() async throws -> DepthCapture { try SampleScene.makeCapture(includeDepth: true) }
    func captureSecondaryImage() async throws -> Data { Data([0xFF, 0xD8]) }
}

@MainActor
struct ClassicTrackingScanTests {
    private func makeScan(
        scanner: any ARScannerServiceProtocol = SimulatedScannerService(capabilities: .simulated, startupDelay: .zero, captureDelay: .zero),
        nutrition: any NutritionServiceProtocol = MockNutritionService(latency: .zero)
    ) throws -> (ScanViewModel, SwiftDataPersistenceService) {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let viewModel = ScanViewModel(
            scanner: scanner,
            nutrition: nutrition,
            persistence: service,
            permissions: MockCameraPermissionService(),
            foodLookup: MockFoodLookupService(latency: .zero)
        )
        return (viewModel, service)
    }

    private func wait(for phase: ScanViewModel.Phase, in viewModel: ScanViewModel) async throws {
        for _ in 0..<1_000 where viewModel.phase != phase {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.phase == phase)
    }

    private func runToReview(_ viewModel: ScanViewModel) async throws {
        try await wait(for: .ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await wait(for: .awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.analyze()
    }

    private func manualDraft(_ name: String = "Banana", grams: Double = 120) throws -> FoodItemDraft {
        let food = try #require(MockFoodLookupService.catalog.first { $0.name == name })
        let portion = try #require(PortionCalculator.portion(manualGrams: grams))
        return FoodItemDraft(id: UUID(), name: food.name, category: food.category, portion: portion, macrosPer100Grams: food.macrosPer100Grams, boundingBox: nil)
    }

    // MARK: Weight override

    @Test func typedWeightRecalculatesTheMacrosImmediately() async throws {
        let (viewModel, _) = try makeScan()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        try await wait(for: .review, in: viewModel)

        let draft = try #require(viewModel.drafts.first)
        let otherItems = viewModel.totalMacros.energyKilocalories - draft.totalMacros.energyKilocalories
        let per100 = draft.macrosPer100Grams.energyKilocalories

        #expect(viewModel.setGrams(for: draft.id, text: "250,5"))

        let edited = try #require(viewModel.drafts.first { $0.id == draft.id })
        #expect(edited.portion.grams == 250.5)
        #expect(edited.portion.source == .userAdjusted)
        #expect(abs(edited.totalMacros.energyKilocalories - per100 * 2.505) < 1e-9)
        #expect(abs(viewModel.totalMacros.energyKilocalories - (otherItems + per100 * 2.505)) < 1e-9)
    }

    @Test(arguments: ["", "abc", "0", "0.5", "3001", "-10"])
    func unusableTypedWeightChangesNothing(text: String) async throws {
        let (viewModel, _) = try makeScan()
        viewModel.addManualItem(try manualDraft(grams: 120))
        let id = try #require(viewModel.drafts.first).id

        #expect(!viewModel.setGrams(for: id, text: text))

        #expect(viewModel.drafts.first?.portion.grams == 120)
        #expect(viewModel.drafts.first?.portion.source == .manualEntry)
    }

    @Test func retypingTheSameWeightDoesNotMarkItAdjusted() throws {
        let (viewModel, _) = try makeScan()
        viewModel.addManualItem(try manualDraft(grams: 120))
        let id = try #require(viewModel.drafts.first).id
        #expect(viewModel.setGrams(for: id, text: "120"))
        #expect(viewModel.drafts.first?.portion.source == .manualEntry)
    }

    // MARK: Adding items

    @Test func manualItemStartsAMealWithoutAPhoto() async throws {
        let (viewModel, service) = try makeScan()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await wait(for: .ready, in: viewModel)
        #expect(viewModel.showsCaptureCard)
        #expect(viewModel.canAddManualItems)

        viewModel.addManualItem(try manualDraft())

        #expect(viewModel.phase == .review)
        #expect(!viewModel.showsCaptureCard)
        #expect(viewModel.capture == nil)
        #expect(!viewModel.usesSampleAnalysis)   // no Gemini result to label as a sample

        await viewModel.saveMeal()
        #expect(viewModel.phase == .saved)
        let meal = try #require(try service.meals(on: .now).first)
        #expect(meal.imageFileName == nil)
        #expect(meal.orderedItems.first?.name == "Banana")
        #expect(meal.orderedItems.first?.portionSource == .manualEntry)
        #expect(abs(meal.totalMacros.energyKilocalories - 108) < 1e-9)
    }

    @Test func manualItemJoinsAScannedMeal() async throws {
        let (viewModel, service) = try makeScan()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        try await wait(for: .review, in: viewModel)
        let scannedCount = viewModel.drafts.count

        viewModel.addManualItem(try manualDraft())

        #expect(viewModel.drafts.count == scannedCount + 1)
        #expect(viewModel.showsCaptureCard)
        #expect(viewModel.capture != nil)
        #expect(!viewModel.hasUnestimatedItems)

        await viewModel.saveMeal()
        let meal = try #require(try service.meals(on: .now).first)
        #expect(meal.items.count == scannedCount + 1)
        #expect(meal.imageFileName != nil)
    }

    @Test func aFailedScanCanContinueManuallyAndKeepsItsPhoto() async throws {
        let (viewModel, _) = try makeScan(nutrition: MockNutritionService(behavior: .failure(.offline), latency: .zero))
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        for _ in 0..<1_000 {
            if case .failed = viewModel.phase { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.canAddManualItems)

        viewModel.addManualItem(try manualDraft())

        #expect(viewModel.phase == .review)
        #expect(viewModel.drafts.map(\.name) == ["Banana"])
        #expect(viewModel.capture != nil)
    }

    /// Comparing counts would let a manual item cancel out the missing one.
    @Test func manualItemsDoNotHideAMissingEstimateWarning() async throws {
        let (viewModel, _) = try makeScan(nutrition: LosesOneEstimate())
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        try await wait(for: .review, in: viewModel)
        #expect(viewModel.hasUnestimatedItems)

        viewModel.addManualItem(try manualDraft())
        #expect(viewModel.hasUnestimatedItems)
    }

    @Test func manualItemsDoNotCauseAWarningOnACompleteScan() async throws {
        let (viewModel, _) = try makeScan()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        try await wait(for: .review, in: viewModel)

        viewModel.addManualItem(try manualDraft())
        #expect(!viewModel.hasUnestimatedItems)
        let scanned = try #require(viewModel.drafts.first { $0.portion.source != .manualEntry })
        viewModel.removeDraft(id: scanned.id)
        #expect(!viewModel.hasUnestimatedItems)
    }

    @Test func cannotAddWhileAnalyzing() async throws {
        let (viewModel, _) = try makeScan(nutrition: MockNutritionService(latency: .seconds(5)))
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await runToReview(viewModel)
        try await wait(for: .detecting, in: viewModel)

        #expect(!viewModel.canAddManualItems)
        viewModel.addManualItem(try manualDraft())
        #expect(viewModel.drafts.isEmpty)
        #expect(viewModel.phase == .detecting)
        viewModel.cancelAnalysis()
    }

    @Test func startingOverClearsManualItems() throws {
        let (viewModel, _) = try makeScan()
        viewModel.addManualItem(try manualDraft())
        viewModel.reset()
        #expect(viewModel.drafts.isEmpty)
    }

    // MARK: Camera handover

    @Test func barcodeTakesTheCameraAndGivesItBack() async throws {
        let scanner = RecordingScanner()
        let (viewModel, _) = try makeScan(scanner: scanner)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await wait(for: .ready, in: viewModel)

        let tracking = viewModel.makeManualTracking(mode: .barcode)
        #expect(scanner.calls == ["start"])
        await viewModel.pauseScannerForBarcode()
        #expect(scanner.calls == ["start", "stop"])
        _ = tracking

        viewModel.resumeScannerAfterBarcode()
        try await wait(for: .ready, in: viewModel)
        #expect(scanner.calls == ["start", "stop", "start"])
    }

    @Test func searchingNeverTouchesTheCamera() async throws {
        let scanner = RecordingScanner()
        let (viewModel, _) = try makeScan(scanner: scanner)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await wait(for: .ready, in: viewModel)

        viewModel.resumeScannerAfterBarcode()   // the sheet closing, with no barcode camera used
        try await Task.sleep(for: .milliseconds(30))
        #expect(scanner.calls == ["start"])
    }

    @Test func addingFromBarcodeKeepsTheReviewWhenTheCameraReturns() async throws {
        let scanner = RecordingScanner()
        let (viewModel, _) = try makeScan(scanner: scanner)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await wait(for: .ready, in: viewModel)

        await viewModel.pauseScannerForBarcode()
        #expect(viewModel.canAddManualItems)
        viewModel.addManualItem(try manualDraft())
        viewModel.resumeScannerAfterBarcode()
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .review)
        #expect(viewModel.drafts.count == 1)
    }

    @Test func aFailedCameraRestartDoesNotDisturbAReview() async throws {
        let scanner = RecordingScanner()
        let (viewModel, _) = try makeScan(scanner: scanner)
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        try await wait(for: .ready, in: viewModel)

        await viewModel.pauseScannerForBarcode()
        viewModel.addManualItem(try manualDraft())
        scanner.startError = .frameUnavailable
        viewModel.resumeScannerAfterBarcode()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.phase == .review)
    }
}
