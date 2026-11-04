// MacroDepthTests/AppConfigurationTests.swift

import Testing
@testable import MacroDepth

struct AppConfigurationTests {
    private let validKey = "AIzaSyTestKey0123456789abcdef"

    @Test func loadsValidConfiguration() throws {
        let result = AppConfiguration.load(fromInfoDictionary: [
            "GEMINI_API_KEY": "  \(validKey)\n",
            "GEMINI_MODEL_ID": "gemini-3.6-flash",
        ])
        let configuration = try result.get()
        #expect(configuration.apiKey == validKey)
        #expect(configuration.modelID == "gemini-3.6-flash")
        #expect(configuration.apiBaseURL.host() == "generativelanguage.googleapis.com")
    }

    @Test func missingModelFallsBackToDefault() throws {
        let configuration = try AppConfiguration.load(fromInfoDictionary: ["GEMINI_API_KEY": validKey]).get()
        #expect(configuration.modelID == AppConfiguration.defaultModelID)
    }

    @Test func reportsKeyProblems() {
        let key = AppConfiguration.apiKeyInfoKey
        #expect(AppConfiguration.load(fromInfoDictionary: [:]) == .failure(.missingValue(key: key)))
        #expect(AppConfiguration.load(fromInfoDictionary: [key: ""]) == .failure(.emptyValue(key: key)))
        #expect(AppConfiguration.load(fromInfoDictionary: [key: "$(GEMINI_API_KEY)"]) == .failure(.unexpandedBuildSetting(key: key)))
        #expect(AppConfiguration.load(fromInfoDictionary: [key: AppConfiguration.placeholderAPIKey]) == .failure(.placeholderValue(key: key)))
        #expect(AppConfiguration.load(fromInfoDictionary: [key: 42]) == .failure(.missingValue(key: key)))
    }

    @Test func rejectsInvalidModelID() {
        let result = AppConfiguration.load(fromInfoDictionary: [
            "GEMINI_API_KEY": validKey,
            "GEMINI_MODEL_ID": "Gemini Flash!",
        ])
        guard case .failure(.invalidValue(let key, _)) = result else {
            Issue.record("Expected invalidValue, got \(result)")
            return
        }
        #expect(key == AppConfiguration.modelIDInfoKey)
    }

    @Test func redactsKey() {
        let configuration = AppConfiguration(apiKey: validKey, modelID: "m")
        #expect(configuration.redactedAPIKey == "AIza…cdef")
        #expect(!configuration.redactedAPIKey.contains("TestKey"))
    }
}
