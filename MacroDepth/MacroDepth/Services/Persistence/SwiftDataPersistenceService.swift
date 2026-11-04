// Services/Persistence/SwiftDataPersistenceService.swift

import Foundation
import os
import SwiftData

@MainActor
final class SwiftDataPersistenceService: PersistenceServiceProtocol {
    static let schema = Schema([MealEntry.self, LoggedFoodItem.self])

    let container: ModelContainer
    let isStoredInMemoryOnly: Bool

    private let imageStore: CaptureImageStore
    private let calendar: Calendar
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacroDepth", category: "Persistence")

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
        // The record is gone; a leftover image file is harmless, so don't fail the delete.
        if let imageFileName {
            await removeImageIgnoringErrors(fileName: imageFileName)
        }
    }

    func imageURL(for meal: MealEntry) -> URL? {
        meal.imageFileName.map { imageStore.url(for: $0) }
    }

    // MARK: Preview data

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
