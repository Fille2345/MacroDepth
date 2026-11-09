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
            if trimmedSearchText.isEmpty { clearSearch() }
        }
    }
    /// Whole foods matching the text so far. They need no network, so unlike the
    /// database search they can follow typing, and they stay if that search fails.
    var genericResults: [FoodProduct] { GenericFoodCatalog.search(searchText) }
    var hasSearchText: Bool { !trimmedSearchText.isEmpty }
    /// The database results shown are for the text in the field, not an earlier search.
    var hasSearchedCurrentText: Bool { searchedQuery == trimmedSearchText }
    /// What the current database results are for. `nil` before the first search.
    private(set) var searchedQuery: String?
    private(set) var searchResults: [FoodProduct] = []
    private(set) var isSearching = false
    private(set) var searchError: String?

    /// The food being weighed. Setting it opens the weight screen, suggesting the weight
    /// used last time for a remembered food and a typical serving otherwise.
    var selectedProduct: FoodProduct? {
        didSet {
            guard let selectedProduct else {
                gramsText = ""
                return
            }
            let remembered = (remembered.favorites + remembered.recents).first { $0.id == selectedProduct.id }
            let grams = remembered?.lastGrams ?? selectedProduct.typicalServingGrams
            gramsText = grams.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        }
    }
    var gramsText = ""

    /// Favorites and recently added foods, shown before the user searches.
    private(set) var remembered = RememberedFoods()
    private(set) var rememberError: String?

    let usesSampleData: Bool

    @ObservationIgnored private let lookup: any FoodLookupServiceProtocol
    /// `nil` where foods aren't remembered, as in some tests.
    @ObservationIgnored private let persistence: (any PersistenceServiceProtocol)?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let permissions: any CameraPermissionProviding
    @ObservationIgnored private let prepareCameraHandover: @MainActor () async -> Void
    @ObservationIgnored private let cameraExists: Bool
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        mode: Mode,
        lookup: any FoodLookupServiceProtocol,
        permissions: any CameraPermissionProviding,
        persistence: (any PersistenceServiceProtocol)? = nil,
        cameraExists: Bool = AVCaptureDevice.default(for: .video) != nil,
        now: @escaping @MainActor () -> Date = { .now },
        prepareCameraHandover: @escaping @MainActor () async -> Void = {}
    ) {
        self.mode = mode
        self.lookup = lookup
        self.persistence = persistence
        self.now = now
        self.permissions = permissions
        self.cameraExists = cameraExists
        self.prepareCameraHandover = prepareCameraHandover
        usesSampleData = lookup is MockFoodLookupService
        loadRememberedFoods()
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
            lookupState = .failed(Self.message(for: error))
        }
    }

    func resetLookup() {
        lookupState = .idle
    }

    // MARK: Search

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Searches when the user submits, never per keystroke: Open Food Facts allows 10 searches
    /// a minute and says search-as-you-type gets clients blocked. Resubmitting an answered
    /// query does nothing, so it doesn't use up that allowance.
    func submitSearch() {
        let query = trimmedSearchText
        guard !query.isEmpty, query != searchedQuery || searchError != nil else { return }
        searchTask?.cancel()
        searchError = nil
        isSearching = true
        searchTask = Task { [weak self] in
            await self?.runSearch(query)
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchedQuery = nil
        searchError = nil
        isSearching = false
    }

    private func runSearch(_ query: String) async {
        do {
            let results = try await lookup.searchFoods(matching: query)
            // A newer search has replaced this one, so its results are out of date.
            guard !Task.isCancelled else { return }
            searchResults = results
            searchedQuery = query
            searchError = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            searchResults = []
            searchedQuery = query
            searchError = Self.message(for: error)
        }
        isSearching = false
    }

    /// Includes the recovery advice, such as waiting out a rate limit.
    private static func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.fullDescription ?? error.localizedDescription
    }

    // MARK: Favorites and recents

    var hasRememberedFoods: Bool { !remembered.favorites.isEmpty || !remembered.recents.isEmpty }

    func isFavorite(_ product: FoodProduct) -> Bool {
        remembered.favorites.contains { $0.id == product.id }
    }

    func toggleFavorite(_ product: FoodProduct) {
        updateRememberedFoods { try $0.setFavorite(product, isFavorite: !isFavorite(product)) }
    }

    func forgetRecent(_ food: RememberedFood) {
        updateRememberedFoods { try $0.forgetRecentFood(id: food.id) }
    }

    private func loadRememberedFoods() {
        guard let persistence else { return }
        do {
            remembered = try persistence.rememberedFoods(recentLimit: QuickRelog.recentLimit)
            rememberError = nil
        } catch {
            rememberError = Self.message(for: error)
        }
    }

    private func updateRememberedFoods(_ change: (any PersistenceServiceProtocol) throws -> Void) {
        guard let persistence else { return }
        do {
            try change(persistence)
            loadRememberedFoods()
        } catch {
            rememberError = Self.message(for: error)
        }
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

    /// The draft to add to the meal. Remembers the food and weight for next time;
    /// failing to remember it doesn't stop the food being added.
    func addEntry() -> FoodItemDraft? {
        guard let draft = makeDraft(), let selectedProduct else { return nil }
        if let persistence {
            do {
                try persistence.recordFoodUse(selectedProduct, grams: draft.portion.grams, at: now())
            } catch {
                rememberError = Self.message(for: error)
            }
        }
        return draft
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
