// Domain/Errors/ConfigurationError.swift

import Foundation

enum ConfigurationError: Error, Equatable, Sendable, LocalizedError {
    case emptyValue(key: String)
    case placeholderValue(key: String)
    case invalidValue(key: String, reason: String)

    var key: String {
        switch self {
        case .emptyValue(let key), .placeholderValue(let key), .invalidValue(let key, _):
            key
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyValue(let key): "Enter a \(key)."
        case .placeholderValue(let key): "That's the example text, not a real \(key)."
        case .invalidValue(let key, let reason): "That \(key) can't be used: \(reason)."
        }
    }

    var recoverySuggestion: String? {
        "Copy your key from Google AI Studio and paste it here."
    }
}

extension LocalizedError {
    /// Description and recovery suggestion joined for display.
    var fullDescription: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }
}
