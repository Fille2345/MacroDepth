// Support/AppConfiguration.swift

import Foundation

/// Runtime configuration read from Info.plist, which receives its values from
/// the .xcconfig files at build time (`GEMINI_API_KEY = $(GEMINI_API_KEY)`).
///
/// Loading never crashes. A missing or invalid key is reported as a
/// `ConfigurationError` so the app can still run with mock services.
struct AppConfiguration: Sendable, Equatable {
    static let apiKeyInfoKey = "GEMINI_API_KEY"
    static let modelIDInfoKey = "GEMINI_MODEL_ID"
    static let defaultModelID = "gemini-3.5-flash"
    static let placeholderAPIKey = "your-gemini-api-key"
    // Kept in code rather than .xcconfig, where "//" would start a comment.
    static let defaultAPIBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    let apiKey: String
    let modelID: String
    let apiBaseURL: URL

    init(apiKey: String, modelID: String, apiBaseURL: URL = AppConfiguration.defaultAPIBaseURL) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.apiBaseURL = apiBaseURL
    }

    static func load(from bundle: Bundle = .main) -> Result<AppConfiguration, ConfigurationError> {
        load(fromInfoDictionary: bundle.infoDictionary ?? [:])
    }

    static func load(fromInfoDictionary info: [String: Any]) -> Result<AppConfiguration, ConfigurationError> {
        let apiKey: String
        switch requiredString(forKey: apiKeyInfoKey, in: info) {
        case .success(let value): apiKey = value
        case .failure(let error): return .failure(error)
        }
        guard apiKey != placeholderAPIKey else {
            return .failure(.placeholderValue(key: apiKeyInfoKey))
        }
        guard !apiKey.contains(where: \.isWhitespace) else {
            return .failure(.invalidValue(key: apiKeyInfoKey, reason: "contains whitespace"))
        }

        // The model ID is optional; anything other than a missing value must be valid.
        let modelID: String
        switch requiredString(forKey: modelIDInfoKey, in: info) {
        case .success(let value):
            guard isValidModelID(value) else {
                return .failure(.invalidValue(key: modelIDInfoKey, reason: "use lowercase letters, digits, '.' and '-' only"))
            }
            modelID = value
        case .failure:
            modelID = defaultModelID
        }

        return .success(AppConfiguration(apiKey: apiKey, modelID: modelID))
    }

    /// The key with everything but its first and last four characters hidden.
    var redactedAPIKey: String {
        guard apiKey.count > 8 else { return String(repeating: "•", count: apiKey.count) }
        return "\(apiKey.prefix(4))…\(apiKey.suffix(4))"
    }

    // MARK: Private

    private static func requiredString(forKey key: String, in info: [String: Any]) -> Result<String, ConfigurationError> {
        guard let raw = info[key] as? String else { return .failure(.missingValue(key: key)) }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .failure(.emptyValue(key: key)) }
        guard !value.contains("$(") else { return .failure(.unexpandedBuildSetting(key: key)) }
        return .success(value)
    }

    private static func isValidModelID(_ value: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.count <= 64 && value.allSatisfy { allowed.contains($0) }
    }
}
