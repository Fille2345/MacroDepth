// Domain/Errors/ConfigurationError.swift

import Foundation

enum ConfigurationError: Error, Equatable, Sendable, LocalizedError {
    case missingValue(key: String)
    case emptyValue(key: String)
    case unexpandedBuildSetting(key: String)
    case placeholderValue(key: String)
    case invalidValue(key: String, reason: String)

    var key: String {
        switch self {
        case .missingValue(let key), .emptyValue(let key), .unexpandedBuildSetting(let key),
             .placeholderValue(let key), .invalidValue(let key, _):
            key
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingValue(let key): "\(key) is missing from Info.plist."
        case .emptyValue(let key): "\(key) is empty."
        case .unexpandedBuildSetting(let key): "\(key) wasn't expanded at build time."
        case .placeholderValue(let key): "\(key) still contains the example placeholder."
        case .invalidValue(let key, let reason): "\(key) is invalid: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        "Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig, set \(key), then run xcodegen generate and rebuild."
    }
}

extension LocalizedError {
    /// Description and recovery suggestion joined for display.
    var fullDescription: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }
}
