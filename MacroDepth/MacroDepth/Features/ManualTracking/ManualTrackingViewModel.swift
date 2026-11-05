// Features/ManualTracking/ManualTrackingViewModel.swift

import AVFoundation
import Foundation
import Observation

/// Drives the sheet for finding a food by barcode or name and choosing its weight.
@MainActor
@Observable
final class ManualTrackingViewModel: Identifiable {
    enum Mode: Hashable {
        case barcode
        case search
    }

    enum CameraState: Equatable {
        case preparing
        case ready
        case denied
        /// No camera, as in the Simulator. Typing the code still works.
        case unavailable
    }

    enum LookupState: Equatable {
        case idle
        case lookingUp
        case invalidCode
        case notFound(String)
        case failed(String)
    }

    private(set) var mode: Mode
    private(set) var cameraState = CameraState.preparing

    var barcodeText = ""
    private(set) var lookupState = LookupState.idle

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }
    private(set) var searchResults: [FoodProduct] = []
    private(set) var isSearching = false
    private(set) var searchError: String?

    /// The food being weighed. Setting it opens the weight screen.
    var selectedProduct: FoodProduct? {
        didSet {
            gramsText = selectedProduct.map { $0.typicalServingGrams.formatted(.number.grouping(.never)) } ?? ""
        }
    }
    var gramsText = ""

    let usesSampleData: Bool

    @ObservationIgnored private let lookup: any FoodLookupServiceProtocol
    @ObservationIgnored private let permissions: any CameraPermissionProviding
    @ObservationIgnored private let prepareCameraHandover: @MainActor () async -> Void
    @ObservationIgnored private let cameraExists: Bool
    @ObservationIgnored private let searchDebounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        mode: Mode,
        lookup: any FoodLookupServiceProtocol,
        permissions: any CameraPermissionProviding,
        cameraExists: Bool = AVCaptureDevice.default(for: .video) != nil,
        searchDebounce: Duration = .milliseconds(300),
        prepareCameraHandover: @escaping @MainActor () async -> Void = {}
    ) {
        self.mode = mode
        self.lookup = lookup
        self.permissions = permissions
        self.cameraExists = cameraExists
        self.searchDebounce = searchDebounce
        self.prepareCameraHandover = prepareCameraHandover
        usesSampleData = lookup is MockFoodLookupService
    }

    func switchMode(to mode: Mode) {
        self.mode = mode
        lookupState = .idle
    }

    // MARK: Barcode

    /// The camera should only look for codes while nothing else is happening.
    var isCameraScanning: Bool {
        cameraState == .ready && lookupState == .idle && selectedProduct == nil
    }

    /// Takes the camera from the AR session, which can't share it, then checks permission.
    func prepareCamera() async {
        guard cameraExists else {
            cameraState = .unavailable
            return
        }
        await prepareCameraHandover()
        switch await permissions.requestAccess() {
        case .authorized: cameraState = .ready
        case .denied, .restricted, .notDetermined: cameraState = .denied
        }
    }

    func cameraFailed() {
        cameraState = .unavailable
    }

    func lookUpBarcode(_ text: String) async {
        guard lookupState == .idle || lookupState == .invalidCode else { return }
        guard let code = FoodBarcode.normalized(text) else {
            lookupState = .invalidCode
            return
        }
        lookupState = .lookingUp
        do {
            if let product = try await lookup.product(forBarcode: code) {
                lookupState = .idle
                selectedProduct = product
            } else {
                lookupState = .notFound(code)
            }
        } catch {
            lookupState = .failed(error.localizedDescription)
        }
    }

    func resetLookup() {
        lookupState = .idle
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        searchError = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, searchDebounce] in
            // Wait for a pause in typing, rather than searching on every letter.
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(query)
        }
    }

    func retrySearch() {
        scheduleSearch()
    }

    private func runSearch(_ query: String) async {
        do {
            let results = try await lookup.searchFoods(matching: query)
            // A newer search has replaced this one, so its results are out of date.
            guard !Task.isCancelled else { return }
            searchResults = results
            searchError = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            searchResults = []
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    // MARK: Weight

    var parsedGrams: Double? {
        OnboardingViewModel.parse(gramsText).flatMap { PortionCalculator.manualEntryRange.contains($0) ? $0 : nil }
    }

    var gramsError: String? {
        guard !gramsText.isEmpty, parsedGrams == nil else { return nil }
        return "Enter a weight from \(Int(PortionCalculator.manualEntryRange.lowerBound)) to \(Int(PortionCalculator.manualEntryRange.upperBound).formatted()) g."
    }

    /// The selected food at the entered weight, updated as it's typed.
    var entryMacros: MacroNutrients? {
        guard let selectedProduct, let parsedGrams else { return nil }
        return selectedProduct.macrosPer100Grams.forPortion(grams: parsedGrams)
    }

    func makeDraft() -> FoodItemDraft? {
        guard let selectedProduct, let parsedGrams,
              let portion = PortionCalculator.portion(manualGrams: parsedGrams) else { return nil }
        return FoodItemDraft(
            id: UUID(),
            name: selectedProduct.name,
            category: selectedProduct.category,
            portion: portion,
            macrosPer100Grams: selectedProduct.macrosPer100Grams,
            boundingBox: nil
        )
    }
}
