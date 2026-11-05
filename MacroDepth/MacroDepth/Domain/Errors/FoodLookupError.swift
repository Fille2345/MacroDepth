// Domain/Errors/FoodLookupError.swift

import Foundation

enum FoodLookupError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .offline: "You appear to be offline."
        case .serviceUnavailable: "The food database isn't responding."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .offline: "Check your connection and try again."
        case .serviceUnavailable: "Try again in a moment."
        }
    }
}
