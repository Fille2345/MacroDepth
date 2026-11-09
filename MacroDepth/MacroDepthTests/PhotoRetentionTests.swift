// MacroDepthTests/PhotoRetentionTests.swift

import Foundation
import Testing
@testable import MacroDepth

@MainActor
struct PhotoRetentionTests {
    private let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    private func logMeal(_ service: SwiftDataPersistenceService, at timestamp: Date, photo: Bool = true) async throws -> MealEntry {
        try await service.saveMeal(MealDraft(
            timestamp: timestamp,
            mealType: .lunch,
            items: Array(SampleScene.sampleFoodItemDrafts().prefix(2)),
            imageJPEGData: photo ? image : nil
        ))
    }

    private func fileExists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func cutoffIsSevenDaysBack() {
        #expect(PhotoRetention.cutoff(now: now, calendar: Calendar(identifier: .gregorian)) == daysAgo(7))
    }

    @Test func deletesOldPhotosButKeepsTheMealsAndTheirMacros() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let old = try await logMeal(service, at: daysAgo(8))
        let recent = try await logMeal(service, at: daysAgo(6))
        let oldMacros = old.totalMacros
        let oldPhoto = try #require(service.imageURL(for: old))
        let recentPhoto = try #require(service.imageURL(for: recent))

        let result = try await service.pruneExpiredPhotos(now: now)

        #expect(result == PhotoPruneResult(mealsCleared: 1, filesDeleted: 1))
        #expect(!fileExists(oldPhoto))
        #expect(old.imageFileName == nil)
        #expect(fileExists(recentPhoto))
        #expect(recent.imageFileName != nil)

        // The record itself is untouched, so the log and charts still count it.
        let remaining = try service.meals(in: DateInterval(start: daysAgo(30), end: now))
        #expect(remaining.count == 2)
        #expect(remaining.first { $0.id == old.id }?.totalMacros == oldMacros)
        #expect(old.items.count == 2)
    }

    @Test func savedMealTemplatesKeepTheirOwnPhoto() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let old = try await logMeal(service, at: daysAgo(30))
        let template = try await service.makeSavedMeal(from: old, name: "Usual lunch")
        let templatePhoto = try #require(service.imageURL(for: template))

        try await service.pruneExpiredPhotos(now: now)

        #expect(old.imageFileName == nil)
        #expect(fileExists(templatePhoto))
    }

    @Test func secondRunFindsNothingToDo() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        _ = try await logMeal(service, at: daysAgo(10))
        _ = try await logMeal(service, at: daysAgo(10), photo: false)

        #expect(try await service.pruneExpiredPhotos(now: now).mealsCleared == 1)
        #expect(try await service.pruneExpiredPhotos(now: now) == PhotoPruneResult())
    }

    @Test func sweepsOldOrphanFilesButNotOnesBeingSaved() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await logMeal(service, at: daysAgo(1))
        let directory = try #require(service.imageURL(for: meal)).deletingLastPathComponent()

        let staleOrphan = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        let freshOrphan = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try image.write(to: staleOrphan)
        try image.write(to: freshOrphan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-2 * SwiftDataPersistenceService.orphanGracePeriod)],
            ofItemAtPath: staleOrphan.path(percentEncoded: false)
        )
        // A referenced photo older than the grace period must survive the sweep too.
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-2 * SwiftDataPersistenceService.orphanGracePeriod)],
            ofItemAtPath: try #require(service.imageURL(for: meal)).path(percentEncoded: false)
        )

        let result = try await service.pruneExpiredPhotos(now: now)

        #expect(result == PhotoPruneResult(mealsCleared: 0, filesDeleted: 1))
        #expect(!fileExists(staleOrphan))
        #expect(fileExists(freshOrphan))
        #expect(fileExists(service.imageURL(for: meal)))
    }

    @Test func notifiesObserversWhenPhotosAreRemoved() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        _ = try await logMeal(service, at: daysAgo(9))
        var changes = service.changes().makeAsyncIterator()

        try await service.pruneExpiredPhotos(now: now)

        #expect(await changes.next() != nil)
    }

    @Test func launchCleanupPrunesInTheLiveAppOnly() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let old = try await logMeal(service, at: daysAgo(8))
        let photo = try #require(service.imageURL(for: old))

        func dependencies(_ mode: AppDependencies.Mode) -> AppDependencies {
            AppDependencies(
                mode: mode,
                hardwareCapabilities: .simulated,
                scanner: SimulatedScannerService(capabilities: .simulated),
                nutrition: MockNutritionService(latency: .zero),
                persistence: service,
                cameraPermissions: MockCameraPermissionService(),
                apiKeys: GeminiKeyManager(store: InMemoryAPIKeyStore())
            )
        }

        let preview = dependencies(.preview)
        preview.startPhotoCleanup(now: { [now] in now })
        await preview.waitForPhotoCleanup()
        #expect(fileExists(photo))

        let live = dependencies(.live)
        live.startPhotoCleanup(now: { [now] in now })
        live.startPhotoCleanup(now: { [now] in now })   // ignored while one is running
        await live.waitForPhotoCleanup()
        #expect(!fileExists(photo))
        #expect(old.imageFileName == nil)
    }
}
