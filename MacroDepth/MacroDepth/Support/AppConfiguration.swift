// Support/AppConfiguration.swift

import Foundation

/// What a Gemini request needs. The API key comes from the user (Settings,
/// stored in the Keychain) and is never built into the app. The model ID is
/// read from Info.plist, which gets it from `GEMINI_MODEL_ID` in the .xcconfig files.
struct AppConfiguration: Sendable, Equatable {
    static let apiKeyName = "Gemini API key"
    static let modelIDInfoKey = "GEMINI_MODEL_ID"
    static let defaultModelID = "gemini-3.6-flash"
    static let placeholderAPIKey = "your-gemini-api-key"
    static let maximumAPIKeyLength = 256
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

    /// The key as typed or pasted, trimmed and checked for obvious mistakes.
    static func validatedAPIKey(_ text: String) -> Result<String, ConfigurationError> {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.emptyValue(key: apiKeyName)) }
        guard key != placeholderAPIKey else { return .failure(.placeholderValue(key: apiKeyName)) }
        guard !key.contains(where: \.isWhitespace) else {
            return .failure(.invalidValue(key: apiKeyName, reason: "it contains spaces or line breaks"))
        }
        guard key.count <= maximumAPIKeyLength, key.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
            return .failure(.invalidValue(key: apiKeyName, reason: "it doesn't look like an API key"))
        }
        return .success(key)
    }

    /// The model from Info.plist, or the default when it's missing or invalid.
    static func modelID(from bundle: Bundle = .main) -> String {
        modelID(fromInfoDictionary: bundle.infoDictionary ?? [:])
    }

    static func modelID(fromInfoDictionary info: [String: Any]) -> String {
        guard let raw = info[modelIDInfoKey] as? String else { return defaultModelID }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidModelID(value) ? value : defaultModelID
    }

    /// The key with everything but its first and last four characters hidden.
    var redactedAPIKey: String { Self.redact(apiKey) }

    static func redact(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }

    // MARK: Private

    private static func isValidModelID(_ value: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        return !value.isEmpty && value.count <= 64 && value.allSatisfy { allowed.contains($0) }
    }
}
