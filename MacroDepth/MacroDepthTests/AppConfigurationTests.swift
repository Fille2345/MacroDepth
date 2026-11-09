// MacroDepthTests/AppConfigurationTests.swift

import Foundation
import Testing
@testable import MacroDepth

struct AppConfigurationTests {
    private let validKey = "AIzaSyTestKey0123456789abcdef"

    @Test func acceptsAPastedKeyAndTrimsIt() throws {
        #expect(try AppConfiguration.validatedAPIKey("  \(validKey)\n").get() == validKey)
    }

    @Test func rejectsKeyMistakes() {
        let name = AppConfiguration.apiKeyName
        #expect(AppConfiguration.validatedAPIKey("") == .failure(.emptyValue(key: name)))
        #expect(AppConfiguration.validatedAPIKey("  \n") == .failure(.emptyValue(key: name)))
        #expect(AppConfiguration.validatedAPIKey(AppConfiguration.placeholderAPIKey) == .failure(.placeholderValue(key: name)))
        for bad in ["AIza key with spaces", "AIzaé€unicode", String(repeating: "a", count: 300)] {
            guard case .failure(.invalidValue(let key, _)) = AppConfiguration.validatedAPIKey(bad) else {
                Issue.record("Expected \(bad.prefix(20)) to be rejected")
                continue
            }
            #expect(key == name)
        }
    }

    @Test func readsModelIDOrFallsBackToDefault() {
        let key = AppConfiguration.modelIDInfoKey
        #expect(AppConfiguration.modelID(fromInfoDictionary: [key: " gemini-test-1.0 "]) == "gemini-test-1.0")
        #expect(AppConfiguration.modelID(fromInfoDictionary: [:]) == AppConfiguration.defaultModelID)
        #expect(AppConfiguration.modelID(fromInfoDictionary: [key: ""]) == AppConfiguration.defaultModelID)
        #expect(AppConfiguration.modelID(fromInfoDictionary: [key: "Gemini Flash!"]) == AppConfiguration.defaultModelID)
        #expect(AppConfiguration.modelID(fromInfoDictionary: [key: "$(GEMINI_MODEL_ID)"]) == AppConfiguration.defaultModelID)
    }

    @Test func appBundleHasNoAPIKey() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") == nil)
    }

    @Test func redactsKey() {
        let configuration = AppConfiguration(apiKey: validKey, modelID: "m")
        #expect(configuration.redactedAPIKey == "AIza…cdef")
        #expect(!configuration.redactedAPIKey.contains("TestKey"))
        #expect(AppConfiguration.redact("short") == "•••••")
    }
}
