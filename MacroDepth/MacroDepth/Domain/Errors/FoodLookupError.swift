// Domain/Errors/FoodLookupError.swift

import Foundation

enum FoodLookupError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case serviceUnavailable
    /// The database limits how often it can be asked.
    case rateLimited
    /// The product exists, but without the values needed to log it.
    case missingNutrition(productName: String)

    var errorDescription: String? {
        switch self {
        case .offline: "You appear to be offline."
        case .serviceUnavailable: "The food database isn't responding."
        case .rateLimited: "Too many food lookups in a short time."
        case .missingNutrition(let productName): "\(productName) is in the database, but its nutrition values are incomplete."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .offline: "Check your connection and try again."
        case .serviceUnavailable: "Try again in a moment."
        case .rateLimited: "Wait a minute and try again."
        case .missingNutrition: "Try searching for a similar food by name."
        }
    }
}
