// Domain/Health/HealthSyncTypes.swift

import Foundation

/// One day's body weight from Apple Health: the last reading of that day.
struct DailyWeight: Equatable, Sendable {
    /// Start of the calendar day.
    let day: Date
    let kilograms: Double
}

/// A logged meal as written to Apple Health: one food correlation per meal.
struct HealthMealRecord: Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let mealType: MealType
    let macros: MacroNutrients

    /// Changes whenever anything written to Health would change, so an edited meal is
    /// rewritten and an unchanged one is left alone. Rounded so float noise doesn't count.
    var fingerprint: String {
        let values = [
            macros.energyKilocalories, macros.proteinGrams, macros.carbohydrateGrams,
            macros.fatGrams, macros.fiberGrams, timestamp.timeIntervalSince1970,
        ]
        return (values.map { String(format: "%.1f", $0) } + [mealType.rawValue]).joined(separator: "|")
    }

    /// Health's "Carbohydrates" is total carbohydrate, as on US labels. The app tracks
    /// available carbs (EU labels), so fibre is added back here and also written on its own.
    var totalCarbohydrateGrams: Double {
        macros.carbohydrateGrams + macros.fiberGrams
    }
}

enum HealthSyncError: Error, Equatable, Sendable, LocalizedError {
    case unavailable
    case authorizationFailed(String)
    case writeDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn't available on this device."
        case .authorizationFailed(let detail): "Apple Health access couldn't be requested: \(detail)"
        case .writeDenied: "MacroDepth isn't allowed to save nutrition to Apple Health."
        case .failed(let detail): "Syncing with Apple Health failed: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unavailable: nil
        case .writeDenied: "In the Health app, open your profile → Apps → MacroDepth and turn on the nutrition types."
        case .authorizationFailed, .failed: "Try again later."
        }
    }
}
