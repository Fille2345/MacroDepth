// Domain/Analysis/NutritionQuery.swift

import Foundation

/// Optional free text about a meal: preparation, cooking fats, cuts, or a pasted recipe.
enum MealNotes {
    static let maximumLength = 4_000

    /// Trims whitespace and caps the length. Blank notes become `nil`.
    static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maximumLength))
    }
}

/// Input to analysis stage 2: one detected item, with measured volume if available.
struct NutritionQuery: Sendable, Hashable, Identifiable {
    /// Same id as the originating `DetectedFoodItem`.
    let id: UUID
    let label: String
    let category: FoodCategory
    let measuredVolume: VolumeMeasurement?
}

/// Output of analysis stage 2 for one item.
struct NutritionEstimate: Sendable, Hashable, Identifiable {
    let id: UUID
    let label: String
    let category: FoodCategory
    let macrosPer100Grams: MacroNutrients
    /// Model-suggested bulk density, validated later by `PortionCalculator`.
    let suggestedDensity: Double?
    /// Present only when no volume was supplied (photo-only fallback).
    let visualEstimateGrams: Double?
    /// Model confidence in [0, 1].
    let confidence: Double

    init(
        id: UUID,
        label: String,
        category: FoodCategory,
        macrosPer100Grams: MacroNutrients,
        suggestedDensity: Double?,
        visualEstimateGrams: Double?,
        confidence: Double
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.macrosPer100Grams = macrosPer100Grams
        self.suggestedDensity = suggestedDensity
        self.visualEstimateGrams = visualEstimateGrams
        self.confidence = confidence.clampedToUnitInterval
    }
}
