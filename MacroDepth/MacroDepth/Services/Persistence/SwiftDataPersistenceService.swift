// Services/Persistence/SwiftDataPersistenceService.swift

import Foundation
import os
import SwiftData

@MainActor
final class SwiftDataPersistenceService: PersistenceServiceProtocol {
    static let schema = Schema([
        MealEntry.self,
        LoggedFoodItem.self,
        UserProfile.self,
        WeightEntry.self,
        SavedMeal.self,
        SavedMealComponent.self,
    ])

    let container: ModelContainer
    let isStoredInMemoryOnly: Bool

    private let imageStore: CaptureImageStore
    private let calendar: Calendar
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacroDepth", category: "Persistence")
    private let changeBroadcaster = AsyncBroadcaster<Void>()

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, imageStore: CaptureImageStore, isStoredInMemoryOnly: Bool, calendar: Calendar = .current) {
        self.container = container
        self.imageStore = imageStore
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.calendar = calendar
    }

    // MARK: Factories

    static func makePersistent() throws -> SwiftDataPersistenceService {
        let directory = try CaptureImageStore.applicationSupportDirectory()
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: configuration)
            return SwiftDataPersistenceService(
                container: container,
                imageStore: CaptureImageStore(directoryURL: directory),
                isStoredInMemoryOnly: false
            )
        } catch {
            throw PersistenceError.storeUnavailable(error.localizedDescription)
        }
    }

    static func makeInMemory(calendar: Calendar = .current) throws -> SwiftDataPersistenceService {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: configuration)
            return SwiftDataPersistenceService(
                container: container,
                imageStore: CaptureImageStore(directoryURL: CaptureImageStore.temporaryDirectory()),
                isStoredInMemoryOnly: true,
                calendar: calendar
            )
        } catch {
            throw PersistenceError.storeUnavailable(error.localizedDescription)
        }
    }

    // MARK: Queries

    func meals(in interval: DateInterval) throws -> [MealEntry] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(error.localizedDescription)
        }
    }

    func meals(on day: Date) throws -> [MealEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            throw PersistenceError.fetchFailed("Couldn't determine the day containing \(day).")
        }
        return try meals(in: interval)
    }

    // MARK: Mutations

    @discardableResult
    func saveMeal(_ draft: MealDraft) async throws -> MealEntry {
        guard !draft.items.isEmpty else {
            throw PersistenceError.invalidDraft("A meal needs at least one food item.")
        }
        guard draft.items.allSatisfy({ $0.portion.grams.isFinite && $0.portion.grams >= 0 && $0.macrosPer100Grams.isValid }) else {
            throw PersistenceError.invalidDraft("One or more food items have invalid values.")
        }

        let mealID = UUID()
        var imageFileName: String?
        if let imageData = draft.imageJPEGData {
            imageFileName = try await imageStore.write(imageData, id: mealID)
        }

        let meal = MealEntry(
            id: mealID,
            timestamp: draft.timestamp,
            mealType: draft.mealType,
            imageFileName: imageFileName,
            notes: MealNotes.normalized(draft.userNotes)
        )
        context.insert(meal)
        for (index, itemDraft) in draft.items.enumerated() {
            let item = LoggedFoodItem(draft: itemDraft, sortIndex: index)
            context.insert(item)
            meal.items.append(item)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            if let imageFileName {
                await removeImageIgnoringErrors(fileName: imageFileName)
            }
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        return meal
    }

    func deleteMeal(_ meal: MealEntry) async throws {
        let imageFileName = meal.imageFileName
        context.delete(meal)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.deleteFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        // The record is gone; a leftover image file is harmless, so don't fail the delete.
        if let imageFileName {
            await removeImageIgnoringErrors(fileName: imageFileName)
        }
    }

    func imageURL(for meal: MealEntry) -> URL? {
        meal.imageFileName.map { imageStore.url(for: $0) }
    }

    // MARK: Profile

    func currentProfile() throws -> UserProfileDraft? {
        do {
            return try storedProfile()?.draft
        } catch {
            throw PersistenceError.profileFailed(error.localizedDescription)
        }
    }

    func saveProfile(_ draft: UserProfileDraft) throws {
        guard draft.isValid(calendar: calendar) else {
            throw PersistenceError.invalidDraft("Your weight, height or age is outside the supported range.")
        }
        do {
            if let existing = try storedProfile() {
                existing.update(from: draft)
            } else {
                context.insert(UserProfile(draft: draft))
            }
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.profileFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
    }

    private func storedProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Body weight

    func weightEntries(in interval: DateInterval) throws -> [WeightEntry] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.weightFailed(error.localizedDescription)
        }
    }

    func latestWeightEntry() throws -> WeightEntry? {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw PersistenceError.weightFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func saveWeight(kilograms: Double, on date: Date) throws -> WeightEntry {
        guard kilograms.isFinite, UserProfileDraft.weightRange.contains(kilograms) else {
            throw PersistenceError.invalidDraft("Your weight is outside the supported range.")
        }
        guard let day = calendar.dateInterval(of: .day, for: date) else {
            throw PersistenceError.weightFailed("Couldn't determine the day containing \(date).")
        }

        let entry: WeightEntry
        if let existing = try weightEntries(in: day).first {
            existing.weightKg = kilograms
            existing.date = day.start
            entry = existing
        } else {
            entry = WeightEntry(date: day.start, weightKg: kilograms)
            context.insert(entry)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.weightFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        return entry
    }

    func deleteWeightEntry(_ entry: WeightEntry) throws {
        context.delete(entry)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.weightFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
    }

    // MARK: Saved meals

    func savedMeals() throws -> [SavedMeal] {
        let descriptor = FetchDescriptor<SavedMeal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func saveSavedMeal(_ draft: SavedMealDraft) async throws -> SavedMeal {
        let name = try Self.validated(draft)
        let id = UUID()
        var imageFileName: String?
        if let imageData = draft.imageJPEGData {
            imageFileName = try await imageStore.write(imageData, id: id)
        }
        return try await insertSavedMeal(
            id: id,
            name: name,
            notes: MealNotes.normalized(draft.notes),
            imageFileName: imageFileName,
            components: draft.components
        )
    }

    func updateSavedMeal(_ savedMeal: SavedMeal, with draft: SavedMealDraft) async throws {
        let name = try Self.validated(draft)
        var newImageFileName: String?
        if let imageData = draft.imageJPEGData {
            newImageFileName = try await imageStore.write(imageData, id: savedMeal.id)
        }

        for component in savedMeal.components {
            context.delete(component)
        }
        savedMeal.components = []
        savedMeal.name = name
        savedMeal.notes = MealNotes.normalized(draft.notes)
        savedMeal.updatedAt = .now
        if let newImageFileName {
            savedMeal.imageFileName = newImageFileName
        }
        for (index, componentDraft) in draft.components.enumerated() {
            let component = SavedMealComponent(draft: componentDraft, sortIndex: index)
            context.insert(component)
            savedMeal.components.append(component)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
    }

    func deleteSavedMeal(_ savedMeal: SavedMeal) async throws {
        let imageFileName = savedMeal.imageFileName
        context.delete(savedMeal)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.deleteFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        if let imageFileName {
            await removeImageIgnoringErrors(fileName: imageFileName)
        }
    }

    func imageURL(for savedMeal: SavedMeal) -> URL? {
        savedMeal.imageFileName.map { imageStore.url(for: $0) }
    }

    @discardableResult
    func makeSavedMeal(from meal: MealEntry, name: String) async throws -> SavedMeal {
        let draft = SavedMealDraft(
            name: name,
            notes: meal.notes,
            components: meal.orderedItems.map(SavedMealComponentDraft.init(item:))
        )
        let validName = try Self.validated(draft)
        let id = UUID()
        var imageFileName: String?
        if let sourceFileName = meal.imageFileName {
            imageFileName = try await imageStore.copy(fileName: sourceFileName, toID: id)
        }
        return try await insertSavedMeal(
            id: id,
            name: validName,
            notes: draft.notes,
            imageFileName: imageFileName,
            components: draft.components
        )
    }

    @discardableResult
    func logSavedMeal(_ savedMeal: SavedMeal, at timestamp: Date, mealType: MealType?) async throws -> MealEntry {
        guard !savedMeal.components.isEmpty else {
            throw PersistenceError.invalidDraft("A meal needs at least one food item.")
        }

        let mealID = UUID()
        var imageFileName: String?
        if let sourceFileName = savedMeal.imageFileName {
            imageFileName = try await imageStore.copy(fileName: sourceFileName, toID: mealID)
        }

        let meal = MealEntry(
            id: mealID,
            timestamp: timestamp,
            mealType: mealType ?? .suggested(for: timestamp),
            imageFileName: imageFileName,
            notes: savedMeal.notes
        )
        context.insert(meal)
        meal.savedMeal = savedMeal
        for (index, component) in savedMeal.orderedComponents.enumerated() {
            let item = LoggedFoodItem(component: component, sortIndex: index)
            context.insert(item)
            meal.items.append(item)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            if let imageFileName {
                await removeImageIgnoringErrors(fileName: imageFileName)
            }
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        return meal
    }

    /// Checks everything about a draft that doesn't need the store, and returns the clean name.
    private static func validated(_ draft: SavedMealDraft) throws -> String {
        guard let name = SavedMeal.validatedName(draft.name) else {
            throw PersistenceError.invalidDraft("A saved meal needs a name of up to \(SavedMeal.maximumNameLength) characters.")
        }
        guard !draft.components.isEmpty else {
            throw PersistenceError.invalidDraft("A saved meal needs at least one ingredient.")
        }
        guard draft.components.allSatisfy(\.isValid) else {
            throw PersistenceError.invalidDraft("One or more ingredients have invalid values.")
        }
        return name
    }

    private func insertSavedMeal(
        id: UUID,
        name: String,
        notes: String?,
        imageFileName: String?,
        components: [SavedMealComponentDraft]
    ) async throws -> SavedMeal {
        let savedMeal = SavedMeal(id: id, name: name, notes: notes, imageFileName: imageFileName)
        context.insert(savedMeal)
        for (index, componentDraft) in components.enumerated() {
            let component = SavedMealComponent(draft: componentDraft, sortIndex: index)
            context.insert(component)
            savedMeal.components.append(component)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            if let imageFileName {
                await removeImageIgnoringErrors(fileName: imageFileName)
            }
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        changeBroadcaster.send(())
        return savedMeal
    }

    // MARK: Photo retention

    /// Files younger than this may belong to a save that hasn't stored its record yet.
    static let orphanGracePeriod: TimeInterval = 60 * 60

    @discardableResult
    func prunePhotos(ofMealsBefore cutoff: Date) async throws -> PhotoPruneResult {
        let expired: [MealEntry]
        do {
            expired = try context.fetch(FetchDescriptor<MealEntry>(
                predicate: #Predicate { $0.timestamp < cutoff && $0.imageFileName != nil }
            ))
        } catch {
            throw PersistenceError.fetchFailed(error.localizedDescription)
        }

        // Clear the references first. If the files then can't be deleted, they're
        // orphans the next sweep removes; the reverse order could leave records
        // pointing at missing files.
        let expiredFileNames = expired.compactMap(\.imageFileName)
        if !expired.isEmpty {
            for meal in expired {
                meal.imageFileName = nil
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw PersistenceError.saveFailed(error.localizedDescription)
            }
            changeBroadcaster.send(())
        }

        var result = PhotoPruneResult(mealsCleared: expired.count)
        result.filesDeleted = await imageStore.delete(fileNames: expiredFileNames)
        let referenced = try referencedImageFileNames()
        result.filesDeleted += await imageStore.deleteFiles(
            notIn: referenced,
            modifiedBefore: Date.now.addingTimeInterval(-Self.orphanGracePeriod)
        )
        return result
    }

    /// Every photo file a meal or template still uses.
    private func referencedImageFileNames() throws -> Set<String> {
        var mealDescriptor = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.imageFileName != nil })
        mealDescriptor.propertiesToFetch = [\.imageFileName]
        var templateDescriptor = FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.imageFileName != nil })
        templateDescriptor.propertiesToFetch = [\.imageFileName]
        do {
            let mealFiles = try context.fetch(mealDescriptor).compactMap(\.imageFileName)
            let templateFiles = try context.fetch(templateDescriptor).compactMap(\.imageFileName)
            return Set(mealFiles + templateFiles)
        } catch {
            throw PersistenceError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: Changes

    func changes() -> AsyncStream<Void> {
        changeBroadcaster.stream()
    }

    // MARK: Preview data

    /// A typical adult profile, so previews show real targets.
    func seedSampleProfile(referenceDate: Date = .now) {
        let draft = UserProfileDraft(
            weightKg: 80,
            heightCm: 180,
            birthYear: calendar.component(.year, from: referenceDate) - 30,
            biologicalSex: .male,
            activityLevel: .moderate,
            goal: .leanBulk
        )
        do {
            try saveProfile(draft)
        } catch {
            logger.error("Seeding the sample profile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Inserts a breakfast and a lunch for `referenceDate` using sample drafts.
    func seedSampleMeals(referenceDate: Date = .now) {
        let drafts = SampleScene.sampleFoodItemDrafts()
        let breakfastTime = calendar.date(bySettingHour: 8, minute: 10, second: 0, of: referenceDate) ?? referenceDate
        let lunchTime = calendar.date(bySettingHour: 12, minute: 25, second: 0, of: referenceDate) ?? referenceDate

        let seeds: [(Date, MealType, [FoodItemDraft])] = [
            (breakfastTime, .breakfast, Array(drafts.prefix(1))),
            (lunchTime, .lunch, drafts),
        ]
        for (timestamp, mealType, items) in seeds {
            let meal = MealEntry(timestamp: timestamp, mealType: mealType)
            context.insert(meal)
            for (index, draft) in items.enumerated() {
                // Fresh ids: the same draft list is reused across meals.
                let copy = FoodItemDraft(
                    id: UUID(),
                    name: draft.name,
                    category: draft.category,
                    portion: draft.portion,
                    macrosPer100Grams: draft.macrosPer100Grams,
                    boundingBox: draft.boundingBox
                )
                let item = LoggedFoodItem(draft: copy, sortIndex: index)
                context.insert(item)
                meal.items.append(item)
            }
        }
        do {
            try context.save()
        } catch {
            logger.error("Seeding sample meals failed: \(error.localizedDescription, privacy: .public)")
        }
        changeBroadcaster.send(())
    }

    /// A month of gently falling weight and most days' meals, for previews.
    func seedSampleProgress(referenceDate: Date = .now) {
        for daysAgo in 1...30 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate) else { continue }
            if !daysAgo.isMultiple(of: 6) {
                seedSampleMeals(referenceDate: date)
            }
            if !daysAgo.isMultiple(of: 4) {
                let wobble = sin(Double(daysAgo) * 1.7) * 0.5
                do {
                    try saveWeight(kilograms: 80 + Double(daysAgo) * 0.05 + wobble, on: date)
                } catch {
                    logger.error("Seeding sample weight failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: Private

    private func removeImageIgnoringErrors(fileName: String) async {
        do {
            try await imageStore.delete(fileName: fileName)
        } catch {
            logger.error("Couldn't remove capture image \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
