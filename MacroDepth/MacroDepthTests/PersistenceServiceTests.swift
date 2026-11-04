// MacroDepthTests/PersistenceServiceTests.swift

import Foundation
import Testing
@testable import MacroDepth

@MainActor
struct PersistenceServiceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
    }

    @Test func savesFetchesAndDeletesMeal() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        let drafts = SampleScene.sampleFoodItemDrafts()
        let draft = MealDraft(
            timestamp: date(3, 12),
            mealType: .lunch,
            items: drafts,
            imageJPEGData: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )

        let meal = try await service.saveMeal(draft)

        let fetched = try service.meals(on: date(3, 20))
        #expect(fetched.count == 1)
        #expect(fetched.first?.orderedItems.map(\.name) == drafts.map(\.name))
        #expect(abs(meal.totalMacros.energyKilocalories - draft.totalMacros.energyKilocalories) < 1e-6)

        let imageURL = try #require(service.imageURL(for: meal))
        #expect(FileManager.default.fileExists(atPath: imageURL.path(percentEncoded: false)))

        try await service.deleteMeal(meal)
        #expect(try service.meals(on: date(3, 12)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path(percentEncoded: false)))
    }

    @Test func fetchIsScopedToTheDay() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        let items = SampleScene.sampleFoodItemDrafts()
        try await service.saveMeal(MealDraft(timestamp: date(2, 23), mealType: .dinner, items: items))
        try await service.saveMeal(MealDraft(timestamp: date(3, 8), mealType: .breakfast, items: Array(items.prefix(1))))

        let today = try service.meals(on: date(3, 15))
        #expect(today.count == 1)
        #expect(today.first?.mealType == .breakfast)
        #expect(try service.meals(on: date(4, 9)).isEmpty)
    }

    @Test func persistsNormalizedNotes() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        let items = SampleScene.sampleFoodItemDrafts()
        try await service.saveMeal(MealDraft(timestamp: date(3, 8), mealType: .breakfast, items: items, userNotes: "  Fried in butter\n"))
        try await service.saveMeal(MealDraft(timestamp: date(3, 12), mealType: .lunch, items: items, userNotes: "   "))

        let meals = try service.meals(on: date(3, 15))
        #expect(meals.map(\.notes) == ["Fried in butter", nil])
    }

    @Test func rejectsEmptyDraft() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        await #expect(throws: PersistenceError.self) {
            // Discard the result: `#expect` returns it as `sending`, and `MealEntry` isn't `Sendable`.
            _ = try await service.saveMeal(MealDraft(timestamp: .now, mealType: .snack, items: []))
        }
    }

    @Test func sampleSceneDepthMatchesGeometry() throws {
        let map = try #require(SampleScene.makeDepthMap())
        let stats = try #require(map.statistics())
        #expect(map.width == SampleScene.depthWidth)
        #expect(stats.coverage == 1)
        #expect(stats.maximumMeters == SampleScene.tableDepthMeters)
        // The tallest item (broccoli, 4 cm) sits on a 1.2 cm plate.
        #expect(abs(stats.minimumMeters - (SampleScene.tableDepthMeters - 0.052)) < 0.002)
    }
}
