// MacroDepthTests/QuickRelogTests.swift

import Foundation
import SwiftData
import Testing
@testable import MacroDepth

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar
}()

private func product(_ id: String, kcal: Double = 200, serving: Double = 100) -> FoodProduct {
    FoodProduct(
        id: id,
        name: "Food \(id)",
        brand: "Brand",
        category: .legume,
        macrosPer100Grams: MacroNutrients(proteinGrams: 20, carbohydrateGrams: 10, fatGrams: 5, fiberGrams: 1, energyKilocalories: kcal),
        typicalServingGrams: serving,
        barcode: nil
    )
}

// MARK: Remembered foods

@MainActor
struct RememberedFoodTests {
    private let service: SwiftDataPersistenceService
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
    }

    @Test func recentsAreNewestFirstWithTheLastWeight() throws {
        try service.recordFoodUse(product("a"), grams: 120, at: start)
        try service.recordFoodUse(product("b"), grams: 80, at: start.addingTimeInterval(60))
        try service.recordFoodUse(product("a"), grams: 140, at: start.addingTimeInterval(120))

        let recents = try service.rememberedFoods(recentLimit: 10).recents
        #expect(recents.map(\.id) == ["a", "b"])
        #expect(recents.first?.lastGrams == 140)
    }

    @Test func keepsTheLatestProductValues() throws {
        try service.recordFoodUse(product("a", kcal: 200), grams: 100, at: start)
        try service.recordFoodUse(product("a", kcal: 180), grams: 100, at: start.addingTimeInterval(60))
        let food = try #require(try service.rememberedFoods(recentLimit: 10).recents.first)
        #expect(food.product.macrosPer100Grams.energyKilocalories == 180)
        #expect(food.product.brand == "Brand")
    }

    @Test func favoritesAreSeparateFromRecents() throws {
        try service.recordFoodUse(product("b"), grams: 100, at: start)
        try service.recordFoodUse(product("a"), grams: 100, at: start)
        try service.setFavorite(product("b"), isFavorite: true)
        try service.setFavorite(product("c"), isFavorite: true)   // never added yet

        let remembered = try service.rememberedFoods(recentLimit: 10)
        #expect(remembered.favorites.map(\.id) == ["b", "c"])
        #expect(remembered.recents.map(\.id) == ["a"])
        #expect(remembered.favorites.allSatisfy { $0.isFavorite })
    }

    @Test func unfavoritingReturnsAUsedFoodToRecentsAndForgetsAnUnusedOne() throws {
        try service.recordFoodUse(product("a"), grams: 100, at: start)
        try service.setFavorite(product("a"), isFavorite: true)
        try service.setFavorite(product("c"), isFavorite: true)

        try service.setFavorite(product("a"), isFavorite: false)
        try service.setFavorite(product("c"), isFavorite: false)

        let remembered = try service.rememberedFoods(recentLimit: 10)
        #expect(remembered.favorites.isEmpty)
        #expect(remembered.recents.map(\.id) == ["a"])
    }

    @Test func forgettingARecentKeepsItsFavorite() throws {
        try service.recordFoodUse(product("a"), grams: 100, at: start)
        try service.recordFoodUse(product("b"), grams: 100, at: start)
        try service.setFavorite(product("b"), isFavorite: true)

        try service.forgetRecentFood(id: "a")
        try service.forgetRecentFood(id: "b")
        try service.forgetRecentFood(id: "missing")

        let remembered = try service.rememberedFoods(recentLimit: 10)
        #expect(remembered.recents.isEmpty)
        #expect(remembered.favorites.map(\.id) == ["b"])
    }

    @Test func keepsAtMostTheNewestNonFavorites() throws {
        try service.setFavorite(product("fav"), isFavorite: true)
        try service.recordFoodUse(product("fav"), grams: 100, at: start)
        for index in 0..<(QuickRelog.maximumRememberedFoods + 5) {
            try service.recordFoodUse(product("\(index)"), grams: 100, at: start.addingTimeInterval(Double(index + 1)))
        }

        let all = try service.rememberedFoods(recentLimit: 1_000)
        #expect(all.recents.count == QuickRelog.maximumRememberedFoods)
        #expect(all.recents.first?.id == "\(QuickRelog.maximumRememberedFoods + 4)")
        #expect(!all.recents.contains { $0.id == "0" })
        #expect(all.favorites.map(\.id) == ["fav"])
        #expect(try service.rememberedFoods(recentLimit: 3).recents.count == 3)
    }

    @Test func rejectsAnInvalidWeight() {
        #expect(throws: PersistenceError.self) {
            try service.recordFoodUse(product("a"), grams: .nan, at: start)
        }
    }
}

// MARK: Manual tracking

@MainActor
struct ManualTrackingQuickRelogTests {
    private let service: SwiftDataPersistenceService

    init() throws {
        service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
    }

    private func make() -> ManualTrackingViewModel {
        ManualTrackingViewModel(
            mode: .search,
            lookup: MockFoodLookupService(latency: .zero),
            permissions: MockCameraPermissionService(),
            persistence: service,
            cameraExists: false
        )
    }

    @Test func addingAFoodRemembersItAndItsWeight() throws {
        let tracking = make()
        tracking.selectedProduct = product("a", serving: 100)
        #expect(tracking.gramsText == "100")
        tracking.gramsText = "175"
        let draft = try #require(tracking.addEntry())
        #expect(draft.portion.grams == 175)

        let next = make()
        #expect(next.remembered.recents.map(\.id) == ["a"])
        next.selectedProduct = next.remembered.recents[0].product
        #expect(next.gramsText == "175")   // last time's weight, not the typical serving
    }

    @Test func invalidWeightAddsAndRemembersNothing() {
        let tracking = make()
        tracking.selectedProduct = product("a")
        tracking.gramsText = "0"
        #expect(tracking.addEntry() == nil)
        #expect(!make().hasRememberedFoods)
    }

    @Test func favoriteToggleUpdatesTheLists() {
        let tracking = make()
        let food = product("a")
        #expect(!tracking.isFavorite(food))

        tracking.toggleFavorite(food)
        #expect(tracking.isFavorite(food))
        #expect(tracking.remembered.favorites.map(\.id) == ["a"])

        tracking.toggleFavorite(food)
        #expect(!tracking.isFavorite(food))
        #expect(!tracking.hasRememberedFoods)
    }

    @Test func forgettingARecentRemovesIt() throws {
        let tracking = make()
        tracking.selectedProduct = product("a")
        _ = tracking.addEntry()
        let food = try #require(make().remembered.recents.first)

        let next = make()
        next.forgetRecent(food)
        #expect(next.remembered.recents.isEmpty)
    }

    @Test func worksWithoutPersistence() {
        let tracking = ManualTrackingViewModel(mode: .search, lookup: MockFoodLookupService(latency: .zero), permissions: MockCameraPermissionService())
        tracking.selectedProduct = product("a")
        #expect(tracking.addEntry() != nil)
        tracking.toggleFavorite(product("a"))
        #expect(!tracking.hasRememberedFoods)
    }

    @Test func scanSheetRemembersFoods() throws {
        let scan = ScanViewModel(
            scanner: SimulatedScannerService(capabilities: .simulated),
            nutrition: MockNutritionService(latency: .zero),
            persistence: service,
            permissions: MockCameraPermissionService()
        )
        let tracking = scan.makeManualTracking(mode: .search)
        tracking.selectedProduct = product("a")
        _ = tracking.addEntry()
        #expect(try service.rememberedFoods(recentLimit: 10).recents.map(\.id) == ["a"])
    }
}

// MARK: Copying meals

@MainActor
struct CopyMealTests {
    private let service: SwiftDataPersistenceService
    private let today = calendar.startOfDay(for: .now)
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }

    init() throws {
        service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
    }

    @discardableResult
    private func logMeal(on day: Date, hour: Int, type: MealType, photo: Bool = false) async throws -> MealEntry {
        try await service.saveMeal(MealDraft(
            timestamp: calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day)!,
            mealType: type,
            items: SampleScene.sampleFoodItemDrafts(),
            imageJPEGData: photo ? Data([0xFF, 0xD8, 0x01]) : nil,
            userNotes: "Meal prep box"
        ))
    }

    @Test func copyKeepsFoodsAndTimeOfDayButNotThePhoto() async throws {
        let original = try await logMeal(on: yesterday, hour: 12, type: .lunch, photo: true)
        let copy = try await service.copyMeal(original, to: today)

        #expect(copy.id != original.id)
        #expect(copy.copiedFromMealID == original.id)
        #expect(copy.timestamp == calendar.date(bySettingHour: 12, minute: 15, second: 0, of: today))
        #expect(copy.mealType == .lunch)
        #expect(copy.notes == "Meal prep box")
        #expect(copy.imageFileName == nil)
        #expect(copy.totalMacros == original.totalMacros)
        #expect(copy.orderedItems.map(\.name) == original.orderedItems.map(\.name))
        #expect(copy.orderedItems.map(\.grams) == original.orderedItems.map(\.grams))
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))

        // Editing the copy's portion doesn't touch the original.
        copy.orderedItems[0].grams += 50
        #expect(copy.totalMacros != original.totalMacros)
        #expect(original.imageFileName != nil)
    }

    @Test func logOffersYesterdaysMealsAndMarksCopies() async throws {
        let breakfast = try await logMeal(on: yesterday, hour: 8, type: .breakfast)
        try await logMeal(on: yesterday, hour: 12, type: .lunch)
        try await logMeal(on: yesterday, hour: 18, type: .dinner)

        let log = LogViewModel(persistence: service, calendar: calendar, initialDay: today)
        log.load()
        #expect(log.previousDayMeals.count == 3)
        #expect(log.previousDayTitle == "From Yesterday")
        #expect(log.meals.isEmpty)

        await log.copy(breakfast)
        #expect(log.meals.count == 1)
        #expect(log.isCopied(breakfast))
        #expect(log.uncopiedPreviousDayMeals.count == 2)

        await log.copy(breakfast)   // already copied: ignored
        #expect(log.meals.count == 1)

        await log.copyAllFromPreviousDay()
        #expect(log.meals.map(\.mealType) == [.breakfast, .lunch, .dinner])
        #expect(log.uncopiedPreviousDayMeals.isEmpty)
        #expect(log.dayTotals.energyKilocalories > 0)
    }

    @Test func copyingNotifiesSoOtherScreensUpdate() async throws {
        let original = try await logMeal(on: yesterday, hour: 12, type: .lunch)
        let stream = service.changes()
        let counter = Task { () -> Int in
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }
        try await service.copyMeal(original, to: today)
        try await Task.sleep(for: .milliseconds(50))
        counter.cancel()
        // The replayed save of the original, then the copy.
        #expect(await counter.value == 2)
    }

    @Test func nothingToOfferAfterAnEmptyDay() throws {
        let log = LogViewModel(persistence: service, calendar: calendar, initialDay: today)
        log.load()
        #expect(log.previousDayMeals.isEmpty)
    }
}
