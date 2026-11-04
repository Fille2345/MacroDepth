// MacroDepthTests/ProgressAndSavedMealPersistenceTests.swift

import Foundation
import SwiftData
import Testing
@testable import MacroDepth

@MainActor
struct WeightEntryPersistenceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
    }

    private func service() throws -> SwiftDataPersistenceService {
        try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
    }

    @Test func savesToTheStartOfTheDayAndFetchesOldestFirst() throws {
        let service = try service()
        try service.saveWeight(kilograms: 81, on: date(5))
        try service.saveWeight(kilograms: 80.5, on: date(3, 7))

        let entries = try service.weightEntries(in: DateInterval(start: date(1, 0), end: date(10, 0)))
        #expect(entries.map(\.weightKg) == [80.5, 81])
        #expect(entries.first?.date == calendar.startOfDay(for: date(3)))
    }

    @Test func aSecondWeighInReplacesThatDay() throws {
        let service = try service()
        try service.saveWeight(kilograms: 80, on: date(3, 0))
        let updated = try service.saveWeight(kilograms: 79.6, on: date(3, 23))

        let entries = try service.weightEntries(in: DateInterval(start: date(1, 0), end: date(10, 0)))
        #expect(entries.count == 1)
        #expect(entries.first?.id == updated.id)
        #expect(entries.first?.weightKg == 79.6)
    }

    @Test func intervalsExcludeTheirEnd() throws {
        let service = try service()
        try service.saveWeight(kilograms: 80, on: date(3))
        try service.saveWeight(kilograms: 81, on: date(4))

        let entries = try service.weightEntries(in: DateInterval(start: date(3, 0), end: date(4, 0)))
        #expect(entries.map(\.weightKg) == [80])
    }

    @Test func latestIsByDateNotByWhenItWasEntered() throws {
        let service = try service()
        #expect(try service.latestWeightEntry() == nil)
        try service.saveWeight(kilograms: 80, on: date(5))
        try service.saveWeight(kilograms: 82, on: date(2))
        #expect(try service.latestWeightEntry()?.weightKg == 80)
    }

    @Test(arguments: [29.9, 300.1, Double.nan, Double.infinity, -80])
    func rejectsImplausibleWeights(kilograms: Double) throws {
        let service = try service()
        #expect(throws: PersistenceError.self) {
            try service.saveWeight(kilograms: kilograms, on: date(3))
        }
        #expect(try service.latestWeightEntry() == nil)
    }

    @Test func deletes() throws {
        let service = try service()
        let entry = try service.saveWeight(kilograms: 80, on: date(3))
        try service.deleteWeightEntry(entry)
        #expect(try service.latestWeightEntry() == nil)
    }

    @Test func savingNotifiesObservers() async throws {
        let service = try service()
        var changes = service.changes().makeAsyncIterator()
        try service.saveWeight(kilograms: 80, on: date(3))
        #expect(await changes.next() != nil)
    }
}

@MainActor
struct SavedMealPersistenceTests {
    private let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])

    private let rice = SavedMealComponentDraft(
        name: "Rice",
        category: .grainOrStarch,
        grams: 200,
        macrosPer100Grams: MacroNutrients(proteinGrams: 2.7, carbohydrateGrams: 28, fatGrams: 0.3, fiberGrams: 0.4, energyKilocalories: 130),
        confidence: 0.8,
        volumeCubicCentimeters: 235,
        densityGramsPerCubicCentimeter: 0.85
    )
    private let chicken = SavedMealComponentDraft(
        name: "Chicken",
        category: .meat,
        grams: 150,
        macrosPer100Grams: MacroNutrients(proteinGrams: 31, carbohydrateGrams: 0, fatGrams: 3.6, energyKilocalories: 165)
    )

    private func draft(name: String = "Chicken bowl", image: Data? = nil) -> SavedMealDraft {
        SavedMealDraft(name: name, notes: "Fried in butter", components: [rice, chicken], imageJPEGData: image)
    }

    private func fileExists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func count<Model: PersistentModel>(_ type: Model.Type, in service: SwiftDataPersistenceService) throws -> Int {
        try service.container.mainContext.fetchCount(FetchDescriptor<Model>())
    }

    /// A logged meal with two items, one of which the user corrected.
    private func loggedMeal(in service: SwiftDataPersistenceService, image: Data? = nil) async throws -> MealEntry {
        var items = SampleScene.sampleFoodItemDrafts()
        items[0].portion = PortionCalculator.adjusted(items[0].portion, toGrams: 321)
        return try await service.saveMeal(MealDraft(
            timestamp: .now,
            mealType: .lunch,
            items: Array(items.prefix(2)),
            imageJPEGData: image,
            userNotes: "Extra sauce"
        ))
    }

    // MARK: Create, read

    @Test func aggregatesMacrosFromItsComponents() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())

        // Rice: 260 kcal, 5.4 g protein. Chicken: 247.5 kcal, 46.5 g protein.
        #expect(abs(saved.totalMacros.energyKilocalories - 507.5) < 1e-9)
        #expect(abs(saved.totalMacros.proteinGrams - 51.9) < 1e-9)
        #expect(saved.orderedComponents.map(\.name) == ["Rice", "Chicken"])

        let first = try #require(saved.orderedComponents.first)
        #expect(first.volumeCubicCentimeters == 235)
        #expect(first.densityGramsPerCubicCentimeter == 0.85)
        #expect(first.category == .grainOrStarch)
    }

    @Test func fetchesMostRecentlyChangedFirst() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let first = try await service.saveSavedMeal(draft(name: "First"))
        try await service.saveSavedMeal(draft(name: "Second"))
        try await service.updateSavedMeal(first, with: draft(name: "First, edited"))

        #expect(try service.savedMeals().map(\.name) == ["First, edited", "Second"])
    }

    @Test func trimsTheName() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft(name: "  Chicken bowl\n"))
        #expect(saved.name == "Chicken bowl")
    }

    @Test func rejectsInvalidDrafts() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        var badGrams = rice
        badGrams.grams = 0
        var badName = rice
        badName.name = "  "
        var badMacros = rice
        badMacros.macrosPer100Grams.fatGrams = -1
        let invalid = [
            draft(name: "   "),
            draft(name: String(repeating: "a", count: SavedMeal.maximumNameLength + 1)),
            SavedMealDraft(name: "Empty", components: []),
            SavedMealDraft(name: "Grams", components: [badGrams]),
            SavedMealDraft(name: "Name", components: [badName]),
            SavedMealDraft(name: "Macros", components: [badMacros]),
        ]
        for invalidDraft in invalid {
            await #expect(throws: PersistenceError.self) {
                _ = try await service.saveSavedMeal(invalidDraft)
            }
        }
        #expect(try service.savedMeals().isEmpty)
        #expect(try count(SavedMealComponent.self, in: service) == 0)
    }

    // MARK: Update

    @Test func updateReplacesComponentsWithoutLeavingOrphans() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())

        try await service.updateSavedMeal(saved, with: SavedMealDraft(name: "Just chicken", components: [chicken]))

        #expect(saved.name == "Just chicken")
        #expect(saved.notes == nil)
        #expect(saved.orderedComponents.map(\.name) == ["Chicken"])
        #expect(try count(SavedMealComponent.self, in: service) == 1)
    }

    @Test func invalidUpdateChangesNothing() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())
        await #expect(throws: PersistenceError.self) {
            try await service.updateSavedMeal(saved, with: SavedMealDraft(name: "Empty", components: []))
        }
        #expect(saved.name == "Chicken bowl")
        #expect(saved.components.count == 2)
    }

    @Test func updateKeepsThePhotoUnlessGivenANewOne() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft(image: photo))
        let url = try #require(service.imageURL(for: saved))

        try await service.updateSavedMeal(saved, with: draft(name: "No new photo"))
        #expect(service.imageURL(for: saved) == url)
        #expect(try Data(contentsOf: url) == photo)

        let newPhoto = Data([0xFF, 0xD8, 0x07, 0xFF, 0xD9])
        try await service.updateSavedMeal(saved, with: draft(name: "New photo", image: newPhoto))
        #expect(try Data(contentsOf: try #require(service.imageURL(for: saved))) == newPhoto)
    }

    // MARK: Delete

    @Test func deleteRemovesComponentsAndPhoto() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft(image: photo))
        let url = service.imageURL(for: saved)

        try await service.deleteSavedMeal(saved)

        #expect(try service.savedMeals().isEmpty)
        #expect(try count(SavedMealComponent.self, in: service) == 0)
        #expect(!fileExists(url))
    }

    @Test func deletingATemplateKeepsMealsLoggedFromIt() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft(image: photo))
        let logged = try await service.logSavedMeal(saved, at: .now, mealType: .lunch)
        let calories = logged.totalMacros.energyKilocalories
        let loggedImage = service.imageURL(for: logged)

        try await service.deleteSavedMeal(saved)

        let meals = try service.meals(on: .now)
        #expect(meals.count == 1)
        #expect(meals.first?.savedMeal == nil)
        #expect(meals.first?.totalMacros.energyKilocalories == calories)
        #expect(fileExists(loggedImage))
    }

    // MARK: Converting a logged meal

    @Test func convertsAMealUsingItsCurrentValues() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await loggedMeal(in: service)

        let saved = try await service.makeSavedMeal(from: meal, name: "Lunch favourite")

        #expect(saved.name == "Lunch favourite")
        #expect(saved.notes == "Extra sauce")
        #expect(saved.orderedComponents.map(\.name) == meal.orderedItems.map(\.name))
        #expect(saved.orderedComponents.first?.grams == 321)   // the user's correction
        #expect(abs(saved.totalMacros.energyKilocalories - meal.totalMacros.energyKilocalories) < 1e-9)
        #expect(meal.savedMeal == nil)                         // it wasn't logged from the template
        #expect(saved.loggedMeals.isEmpty)
    }

    @Test func convertingCarriesMeasuredVolumeAndDensity() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let volume = try #require(VolumeMeasurement(cubicCentimeters: 240, uncertaintyCubicCentimeters: 30, sampleCount: 900, method: .shapeHeuristic))
        let portion = PortionCalculator.portion(volume: volume, suggestedDensity: 0.85, category: .grainOrStarch, modelConfidence: 0.9)
        let item = FoodItemDraft(
            id: UUID(),
            name: "Rice",
            category: .grainOrStarch,
            portion: portion,
            macrosPer100Grams: rice.macrosPer100Grams
        )
        let meal = try await service.saveMeal(MealDraft(timestamp: .now, mealType: .dinner, items: [item]))

        let saved = try await service.makeSavedMeal(from: meal, name: "Rice")

        let component = try #require(saved.components.first)
        #expect(component.volumeCubicCentimeters == 240)
        #expect(component.densityGramsPerCubicCentimeter == 0.85)
        #expect(component.confidence == portion.confidence)
    }

    @Test func templatePhotoSurvivesDeletingTheOriginalMeal() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await loggedMeal(in: service, image: photo)
        let saved = try await service.makeSavedMeal(from: meal, name: "Favourite")
        let templateImage = try #require(service.imageURL(for: saved))
        #expect(templateImage != service.imageURL(for: meal))

        try await service.deleteMeal(meal)

        #expect(try Data(contentsOf: templateImage) == photo)
        #expect(try service.savedMeals().count == 1)
        #expect(saved.components.count == 2)
    }

    @Test func aMissingSourcePhotoDoesNotBlockConverting() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await loggedMeal(in: service, image: photo)
        try FileManager.default.removeItem(at: try #require(service.imageURL(for: meal)))

        let saved = try await service.makeSavedMeal(from: meal, name: "Favourite")
        #expect(saved.imageFileName == nil)
    }

    @Test func convertingRejectsABlankNameAndLeavesNoFiles() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await loggedMeal(in: service, image: photo)
        await #expect(throws: PersistenceError.self) {
            _ = try await service.makeSavedMeal(from: meal, name: "  ")
        }
        #expect(try service.savedMeals().isEmpty)
        let directory = try #require(service.imageURL(for: meal)).deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).count == 1)
    }

    // MARK: Logging a template

    @Test func loggingCreatesALinkedMealInThatDaysLog() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())

        let meal = try await service.logSavedMeal(saved, at: .now, mealType: .dinner)

        #expect(meal.savedMeal?.id == saved.id)
        #expect(saved.loggedMeals.map(\.id) == [meal.id])
        #expect(meal.mealType == .dinner)
        #expect(meal.notes == "Fried in butter")
        #expect(meal.orderedItems.map(\.name) == ["Rice", "Chicken"])
        #expect(meal.orderedItems.allSatisfy { $0.portionSource == .savedMeal })
        #expect(abs(meal.totalMacros.energyKilocalories - saved.totalMacros.energyKilocalories) < 1e-9)
        #expect(try service.meals(on: .now).map(\.id) == [meal.id])
    }

    @Test func mealTypeDefaultsToTheSuggestionForThatTime() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())
        let timestamp = Date.now
        let meal = try await service.logSavedMeal(saved, at: timestamp, mealType: nil)
        #expect(meal.mealType == .suggested(for: timestamp))
    }

    @Test func loggingTwiceMakesTwoIndependentMeals() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())

        let first = try await service.logSavedMeal(saved, at: .now, mealType: .lunch)
        let second = try await service.logSavedMeal(saved, at: .now, mealType: .dinner)

        #expect(try service.meals(on: .now).count == 2)
        #expect(saved.loggedMeals.count == 2)
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))

        try await service.deleteMeal(first)
        #expect(saved.loggedMeals.map(\.id) == [second.id])
        #expect(second.items.count == 2)
        #expect(saved.components.count == 2)
    }

    @Test func editingATemplateDoesNotChangeMealsAlreadyLogged() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())
        let meal = try await service.logSavedMeal(saved, at: .now, mealType: .lunch)
        let calories = meal.totalMacros.energyKilocalories

        try await service.updateSavedMeal(saved, with: SavedMealDraft(name: "Smaller", components: [chicken]))

        #expect(meal.totalMacros.energyKilocalories == calories)
        #expect(meal.items.count == 2)
        #expect(meal.savedMeal?.id == saved.id)
    }

    @Test func deletingALoggedMealKeepsTheTemplatePhoto() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft(image: photo))
        let templateImage = service.imageURL(for: saved)
        let meal = try await service.logSavedMeal(saved, at: .now, mealType: .lunch)
        let mealImage = service.imageURL(for: meal)
        #expect(mealImage != templateImage)
        #expect(fileExists(mealImage))

        try await service.deleteMeal(meal)

        #expect(!fileExists(mealImage))
        #expect(fileExists(templateImage))
    }

    @Test func loggingNotifiesObserversSoTheDashboardUpdates() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let saved = try await service.saveSavedMeal(draft())
        var changes = service.changes().makeAsyncIterator()
        try await service.logSavedMeal(saved, at: .now, mealType: .lunch)
        #expect(await changes.next() != nil)
    }
}

// MARK: - Migration

/// An exact copy of the schema before `WeightEntry` and `SavedMeal` were added, as it
/// exists on devices today. It must not change when the app's models do.
private enum PreviousSchema {
    @Model
    final class MealEntry {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var mealTypeRawValue: String
        var imageFileName: String?
        var notes: String?

        @Relationship(deleteRule: .cascade, inverse: \LoggedFoodItem.meal)
        var items: [LoggedFoodItem] = []

        init(id: UUID, timestamp: Date, mealTypeRawValue: String, imageFileName: String?, notes: String?) {
            self.id = id
            self.timestamp = timestamp
            self.mealTypeRawValue = mealTypeRawValue
            self.imageFileName = imageFileName
            self.notes = notes
        }
    }

    @Model
    final class LoggedFoodItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRawValue: String
        var sortIndex: Int
        var grams: Double
        var portionSourceRawValue: String
        var confidence: Double
        var volumeCubicCentimeters: Double?
        var densityGramsPerCubicCentimeter: Double?
        var proteinGramsPer100g: Double
        var carbohydrateGramsPer100g: Double
        var fatGramsPer100g: Double
        var fiberGramsPer100g: Double
        var energyKilocaloriesPer100g: Double
        var meal: MealEntry?

        init(id: UUID, name: String, grams: Double) {
            self.id = id
            self.name = name
            categoryRawValue = "meat"
            sortIndex = 0
            self.grams = grams
            portionSourceRawValue = "lidarVolume"
            confidence = 0.8
            volumeCubicCentimeters = 190
            densityGramsPerCubicCentimeter = 1.05
            proteinGramsPer100g = 31
            carbohydrateGramsPer100g = 0
            fatGramsPer100g = 3.6
            fiberGramsPer100g = 0
            energyKilocaloriesPer100g = 165
        }
    }

    @Model
    final class UserProfile {
        var weightKg: Double
        var heightCm: Double
        var birthYear: Int
        var biologicalSexRawValue: String
        var activityLevelRawValue: String
        var goalRawValue: String
        var calorieOverride: Double?
        var proteinOverride: Double?
        var carbohydrateOverride: Double?
        var fatOverride: Double?
        var updatedAt: Date

        init(weightKg: Double, biologicalSexRawValue: String, activityLevelRawValue: String, goalRawValue: String) {
            self.weightKg = weightKg
            heightCm = 180
            birthYear = 1996
            self.biologicalSexRawValue = biologicalSexRawValue
            self.activityLevelRawValue = activityLevelRawValue
            self.goalRawValue = goalRawValue
            calorieOverride = 2_800
            updatedAt = .now
        }
    }
}

@MainActor
struct SavedMealMigrationTests {
    @Test func existingStoreUpgradesWithItsDataIntact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("store.sqlite")

        let mealID = UUID()
        let itemID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_790_000_000)

        // Write a store with the previous schema, then close it.
        do {
            let schema = Schema([PreviousSchema.MealEntry.self, PreviousSchema.LoggedFoodItem.self, PreviousSchema.UserProfile.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            let context = ModelContext(container)
            let meal = PreviousSchema.MealEntry(
                id: mealID,
                timestamp: timestamp,
                mealTypeRawValue: MealType.dinner.rawValue,
                imageFileName: "photo.jpg",
                notes: "Old notes"
            )
            context.insert(meal)
            let item = PreviousSchema.LoggedFoodItem(id: itemID, name: "Chicken", grams: 200)
            context.insert(item)
            meal.items.append(item)
            context.insert(PreviousSchema.UserProfile(
                weightKg: 77,
                biologicalSexRawValue: BiologicalSex.male.rawValue,
                activityLevelRawValue: ActivityLevel.moderate.rawValue,
                goalRawValue: FitnessGoal.leanBulk.rawValue
            ))
            try context.save()
        }

        // Open it with the app's current schema, and use the new features on it.
        let schema = SwiftDataPersistenceService.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let service = SwiftDataPersistenceService(
            container: container,
            imageStore: CaptureImageStore(directoryURL: CaptureImageStore.temporaryDirectory()),
            isStoredInMemoryOnly: false
        )

        let meals = try service.meals(in: DateInterval(start: timestamp.addingTimeInterval(-60), end: timestamp.addingTimeInterval(60)))
        let meal = try #require(meals.first)
        #expect(meals.count == 1)
        #expect(meal.id == mealID)
        #expect(meal.mealType == .dinner)
        #expect(meal.notes == "Old notes")
        #expect(meal.savedMeal == nil)
        #expect(meal.items.map(\.id) == [itemID])
        #expect(meal.items.first?.grams == 200)
        #expect(abs(meal.totalMacros.energyKilocalories - 330) < 1e-9)

        let profile = try #require(try service.currentProfile())
        #expect(profile.weightKg == 77)
        #expect(profile.overrides.calories == 2_800)

        let saved = try await service.makeSavedMeal(from: meal, name: "From before the upgrade")
        let logged = try await service.logSavedMeal(saved, at: timestamp, mealType: .lunch)
        #expect(logged.savedMeal?.id == saved.id)
        try service.saveWeight(kilograms: 77, on: timestamp)
        #expect(try service.latestWeightEntry()?.weightKg == 77)
    }
}
