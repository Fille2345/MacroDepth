// MacroDepthTests/GeminiKeyTests.swift

import Foundation
import Testing
@testable import MacroDepth

/// Answers every request with an empty detection result and records the key it was given.
private final class KeyRecordingClient: GeminiAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    var usedKeys: [String] { lock.withLock { keys } }

    func factory() -> KeyedGeminiNutritionService.ClientFactory {
        { [self] configuration in
            lock.withLock { keys.append(configuration.apiKey) }
            return self
        }
    }

    func generateContent(_ request: GeminiGenerateContentRequest) async throws -> String {
        #"{"items":[]}"#
    }
}

@Suite(.serialized)
struct KeychainAPIKeyStoreTests {
    private let store = KeychainAPIKeyStore(service: "MacroDepthTests.\(UUID().uuidString)")

    @Test func savesReplacesAndDeletes() throws {
        defer { try? store.delete() }
        #expect(try store.load() == nil)

        try store.save("AIzaFirstKey")
        #expect(try store.load() == "AIzaFirstKey")

        try store.save("AIzaSecondKey")
        #expect(try store.load() == "AIzaSecondKey")

        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()   // deleting nothing is fine
    }
}

@MainActor
struct GeminiKeyManagerTests {
    @Test func savesTrimmedKeyAndShowsOnlyARedactedForm() throws {
        let store = InMemoryAPIKeyStore()
        let manager = GeminiKeyManager(store: store)
        #expect(!manager.hasKey)

        try manager.save("  AIzaSyTestKey0123456789abcdef \n")
        #expect(try store.load() == "AIzaSyTestKey0123456789abcdef")
        #expect(manager.redactedKey == "AIza…cdef")

        try manager.remove()
        #expect(!manager.hasKey)
        #expect(try store.load() == nil)
    }

    @Test func invalidKeyLeavesTheSavedOneInPlace() throws {
        let store = InMemoryAPIKeyStore(key: "AIzaSyTestKey0123456789abcdef")
        let manager = GeminiKeyManager(store: store)
        #expect(throws: ConfigurationError.self) { try manager.save("not a key") }
        #expect(try store.load() == "AIzaSyTestKey0123456789abcdef")
        #expect(manager.hasKey)
    }

    @Test func liveAppReadsTheKeyFromTheKeychainNotTheBundle() {
        let dependencies = AppDependencies.makeLive()
        #expect(dependencies.nutrition is KeyedGeminiNutritionService)
        #expect(dependencies.apiKeys.store is KeychainAPIKeyStore)
        #expect(AppDependencies.makePreview(apiKey: nil).apiKeys.hasKey == false)
    }
}

struct KeyedGeminiNutritionServiceTests {
    private let image = Data([0xFF, 0xD8, 0x01])

    @Test func throwsMissingKeyWithoutCallingGemini() async {
        let client = KeyRecordingClient()
        let service = KeyedGeminiNutritionService(store: InMemoryAPIKeyStore(), modelID: "m", makeClient: client.factory())
        await #expect(throws: NutritionServiceError.missingAPIKey) {
            _ = try await service.detectFoodItems(in: [image], userNotes: nil)
        }
        #expect(client.usedKeys.isEmpty)
    }

    @Test func usesTheCurrentKeyForEachRequest() async throws {
        let store = InMemoryAPIKeyStore(key: "AIzaFirst")
        let client = KeyRecordingClient()
        let service = KeyedGeminiNutritionService(store: store, modelID: "m", makeClient: client.factory())

        _ = try await service.detectFoodItems(in: [image], userNotes: nil)
        try store.save("AIzaSecond")
        _ = try await service.detectFoodItems(in: [image], userNotes: nil)

        #expect(client.usedKeys == ["AIzaFirst", "AIzaSecond"])
    }
}
