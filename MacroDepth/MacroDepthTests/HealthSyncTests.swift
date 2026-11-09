// MacroDepthTests/HealthSyncTests.swift

import Foundation
import SwiftData
import Testing
@testable import MacroDepth

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar
}()

/// Noon on a fixed day, so day arithmetic is stable.
private let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!

private func day(_ offset: Int) -> Date {
    calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now)!)
}

// MARK: Weight import

@MainActor
struct HealthWeightImportTests {
    private let interval = DateInterval(start: day(-30), end: now)

    @Test func importsHealthWeightsAndLetsAppEntriesWin() throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        try service.saveWeight(kilograms: 80, on: day(-2))

        let changes = try service.importHealthWeights([
            DailyWeight(day: day(-3), kilograms: 81),
            DailyWeight(day: day(-2), kilograms: 79),   // the app's own entry wins
            DailyWeight(day: day(-1), kilograms: 400),  // out of range, ignored
        ], covering: interval)

        #expect(changes == 1)
        let entries = try service.weightEntries(in: interval)
        #expect(entries.map(\.weightKg) == [81, 80])
        #expect(entries.map(\.isFromHealth) == [true, false])
    }

    @Test func followsHealthChangesAndDeletions() throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        try service.importHealthWeights([
            DailyWeight(day: day(-3), kilograms: 81),
            DailyWeight(day: day(-2), kilograms: 80),
        ], covering: interval)

        let changes = try service.importHealthWeights([DailyWeight(day: day(-3), kilograms: 80.5)], covering: interval)

        #expect(changes == 2)
        #expect(try service.weightEntries(in: interval).map(\.weightKg) == [80.5])
    }

    @Test func unchangedImportDoesNotSaveOrNotify() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        let weights = [DailyWeight(day: day(-3), kilograms: 81)]
        try service.importHealthWeights(weights, covering: interval)

        let stream = service.changes()
        let counter = Task { () -> Int in
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }
        #expect(try service.importHealthWeights(weights, covering: interval) == 0)
        try service.saveWeight(kilograms: 70, on: day(-10))   // one real change
        try await Task.sleep(for: .milliseconds(50))
        counter.cancel()
        // The stream replays the first import's change, then gets the weight's; a
        // notifying no-op import would make it 3.
        #expect(await counter.value == 2)
    }

    @Test func enteringAWeightTakesOverAnImportedDay() throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        try service.importHealthWeights([DailyWeight(day: day(-3), kilograms: 81)], covering: interval)
        try service.saveWeight(kilograms: 82, on: day(-3))

        try service.importHealthWeights([DailyWeight(day: day(-3), kilograms: 81)], covering: interval)
        let entry = try #require(try service.weightEntries(in: interval).first)
        #expect(entry.weightKg == 82)
        #expect(!entry.isFromHealth)
    }

    @Test func releasingKeepsImportedWeighInsAsOrdinaryOnes() throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        try service.importHealthWeights([DailyWeight(day: day(-3), kilograms: 81)], covering: interval)
        try service.releaseHealthWeights()

        // Health no longer has it, but it's the user's own entry now.
        try service.importHealthWeights([], covering: interval)
        let entry = try #require(try service.weightEntries(in: interval).first)
        #expect(entry.weightKg == 81)
        #expect(!entry.isFromHealth)
    }

    @Test func progressWontDeleteAHealthWeighIn() throws {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
        try service.importHealthWeights([DailyWeight(day: day(-3), kilograms: 81)], covering: interval)
        let progress = ProgressTrackerViewModel(persistence: service, calendar: calendar, now: { now })
        progress.load()

        let entry = try #require(progress.weightEntries.first)
        progress.deleteWeight(entry)
        #expect(try service.weightEntries(in: interval).count == 1)
    }
}

// MARK: Records

struct HealthMealRecordTests {
    private let macros = MacroNutrients(proteinGrams: 30, carbohydrateGrams: 50, fatGrams: 10, fiberGrams: 6)

    @Test func totalCarbohydrateAddsFibreBack() {
        let record = HealthMealRecord(id: UUID(), timestamp: now, mealType: .lunch, macros: macros)
        #expect(record.totalCarbohydrateGrams == 56)
    }

    @Test func fingerprintChangesWithWhatHealthWouldShow() {
        let record = HealthMealRecord(id: UUID(), timestamp: now, mealType: .lunch, macros: macros)
        var bigger = macros
        bigger.proteinGrams += 5
        #expect(record.fingerprint == HealthMealRecord(id: UUID(), timestamp: now, mealType: .lunch, macros: macros).fingerprint)
        #expect(record.fingerprint != HealthMealRecord(id: record.id, timestamp: now, mealType: .lunch, macros: bigger).fingerprint)
        #expect(record.fingerprint != HealthMealRecord(id: record.id, timestamp: now, mealType: .dinner, macros: macros).fingerprint)
        #expect(record.fingerprint != HealthMealRecord(id: record.id, timestamp: now.addingTimeInterval(60), mealType: .lunch, macros: macros).fingerprint)
    }
}

// MARK: Coordinator

@MainActor
struct HealthSyncCoordinatorTests {
    private let service: SwiftDataPersistenceService
    private let store = InMemoryHealthStore()
    private let defaults = UserDefaults(suiteName: "HealthSyncTests-\(UUID().uuidString)")!

    init() throws {
        service = try SwiftDataPersistenceService.makeInMemory(calendar: calendar)
    }

    private func makeCoordinator(store: InMemoryHealthStore? = nil) -> HealthSyncCoordinator {
        HealthSyncCoordinator(
            store: store ?? self.store,
            persistence: service,
            defaults: defaults,
            calendar: calendar,
            debounce: .zero,
            now: { now }
        )
    }

    @discardableResult
    private func logMeal(daysAgo: Int, grams: Double = 150) async throws -> MealEntry {
        var item = SampleScene.sampleFoodItemDrafts()[0]
        item.portion = PortionCalculator.adjusted(item.portion, toGrams: grams)
        let timestamp = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return try await service.saveMeal(MealDraft(timestamp: timestamp, mealType: .lunch, items: [item], imageJPEGData: nil))
    }

    @Test func enablingWritesRecentMealsAndImportsWeight() async throws {
        let recent = try await logMeal(daysAgo: 2)
        try await logMeal(daysAgo: HealthSyncCoordinator.mealWindowDays + 5)   // too old to backfill
        store.setWeights([DailyWeight(day: day(-1), kilograms: 78.4)])

        let coordinator = makeCoordinator()
        await coordinator.enable()
        await coordinator.waitForSync()

        #expect(coordinator.isEnabled)
        #expect(coordinator.status == .synced(now))
        #expect(Array(store.savedMeals.keys) == [recent.id])
        #expect(store.savedMeals[recent.id]?.macros == recent.totalMacros)
        let weights = try service.weightEntries(in: DateInterval(start: day(-10), end: now))
        #expect(weights.map(\.weightKg) == [78.4])
        #expect(weights.first?.isFromHealth == true)
    }

    @Test func keepsHealthInStepWithTheLog() async throws {
        let coordinator = makeCoordinator()
        await coordinator.enable()
        let observer = Task { await coordinator.observeChanges() }
        defer { observer.cancel() }

        let meal = try await logMeal(daysAgo: 0)
        try await waitUntil { store.savedMeals[meal.id] != nil }

        // Unchanged meals aren't written again.
        let saves = store.saveCallCount
        coordinator.requestSync()
        await coordinator.waitForSync()
        #expect(store.saveCallCount == saves)

        try await service.deleteMeal(meal)
        try await waitUntil { store.savedMeals.isEmpty }
    }

    @Test func restoresAMealDeletedOnlyInHealth() async throws {
        let meal = try await logMeal(daysAgo: 1)
        let coordinator = makeCoordinator()
        await coordinator.enable()
        await coordinator.waitForSync()

        store.removeMealExternally(id: meal.id)
        coordinator.requestSync()
        await coordinator.waitForSync()
        #expect(store.savedMeals[meal.id] != nil)
    }

    @Test func deniedAuthorizationLeavesSyncOff() async {
        store.failAuthorization(with: .authorizationFailed("denied"))
        let coordinator = makeCoordinator()
        await coordinator.enable()

        #expect(!coordinator.isEnabled)
        guard case .failed = coordinator.status else {
            Issue.record("Expected a failure status, got \(coordinator.status)")
            return
        }
        #expect(!defaults.bool(forKey: HealthSyncCoordinator.enabledDefaultsKey))
    }

    @Test func writeFailureIsReported() async throws {
        try await logMeal(daysAgo: 1)
        store.failWrites(with: .writeDenied)
        let coordinator = makeCoordinator()
        await coordinator.enable()
        await coordinator.waitForSync()
        #expect(coordinator.status == .failed(HealthSyncError.writeDenied.fullDescription))
    }

    @Test func choiceIsRememberedAndDisablingReleasesWeights() async throws {
        store.setWeights([DailyWeight(day: day(-1), kilograms: 78)])
        let first = makeCoordinator()
        await first.enable()
        await first.waitForSync()

        let relaunched = makeCoordinator()
        #expect(relaunched.isEnabled)

        relaunched.disable()
        #expect(!makeCoordinator().isEnabled)
        let entry = try #require(try service.weightEntries(in: DateInterval(start: day(-10), end: now)).first)
        #expect(!entry.isFromHealth)

        // Nothing syncs while off.
        try await logMeal(daysAgo: 0)
        relaunched.requestSync()
        await relaunched.waitForSync()
        #expect(store.savedMeals.isEmpty)
    }

    @Test func unavailableHealthNeverTurnsOn() async {
        let coordinator = makeCoordinator(store: InMemoryHealthStore(isAvailable: false))
        defaults.set(true, forKey: HealthSyncCoordinator.enabledDefaultsKey)
        #expect(!makeCoordinator(store: InMemoryHealthStore(isAvailable: false)).isEnabled)
        await coordinator.enable()
        #expect(!coordinator.isEnabled)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out")
        throw CancellationError()
    }
}

// MARK: Migration

private enum PreHealthSchema {
    @Model
    final class WeightEntry {
        @Attribute(.unique) var id: UUID
        var date: Date
        var weightKg: Double

        init(id: UUID, date: Date, weightKg: Double) {
            self.id = id
            self.date = date
            self.weightKg = weightKg
        }
    }
}

@MainActor
struct WeightSourceMigrationTests {
    @Test func existingWeighInsUpgradeAsAppEntered() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeightMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("store.sqlite")

        do {
            let schema = Schema([PreHealthSchema.WeightEntry.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            let context = ModelContext(container)
            context.insert(PreHealthSchema.WeightEntry(id: UUID(), date: day(-1), weightKg: 79))
            try context.save()
        }

        let schema = SwiftDataPersistenceService.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let service = SwiftDataPersistenceService(
            container: container,
            imageStore: CaptureImageStore(directoryURL: CaptureImageStore.temporaryDirectory()),
            isStoredInMemoryOnly: false,
            calendar: calendar
        )
        let entry = try #require(try service.latestWeightEntry())
        #expect(entry.weightKg == 79)
        #expect(!entry.isFromHealth)

        // A Health import for the same day leaves the user's entry alone.
        try service.importHealthWeights([DailyWeight(day: day(-1), kilograms: 70)], covering: DateInterval(start: day(-5), end: now))
        #expect(try service.latestWeightEntry()?.weightKg == 79)
    }
}
