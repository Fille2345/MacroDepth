// Domain/Persistence/LoggedFoodItem.swift

import Foundation
import SwiftData

/// A persisted food item. Macros are stored per 100 g together with the portion
/// weight, so a later weight edit recomputes totals without another API call.
@Model
final class LoggedFoodItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRawValue: String
    var sortIndex: Int

    var grams: Double
    var portionSourceRawValue: String
    var confidence: Double
    var volumeCubicCentimeters: Double?
    var densityGramsPerCubicCentimeter: Double?

    var proteinGramsPer100g: Double
    var carbohydrateGramsPer100g: Double
    var fatGramsPer100g: Double
    var fiberGramsPer100g: Double
    var energyKilocaloriesPer100g: Double

    var meal: MealEntry?

    init(draft: FoodItemDraft, sortIndex: Int) {
        id = draft.id
        name = draft.name
        categoryRawValue = draft.category.rawValue
        self.sortIndex = sortIndex
        grams = draft.portion.grams
        portionSourceRawValue = draft.portion.source.rawValue
        confidence = draft.portion.confidence
        volumeCubicCentimeters = draft.portion.volume?.cubicCentimeters
        densityGramsPerCubicCentimeter = draft.portion.densityGramsPerCubicCentimeter
        proteinGramsPer100g = draft.macrosPer100Grams.proteinGrams
        carbohydrateGramsPer100g = draft.macrosPer100Grams.carbohydrateGrams
        fatGramsPer100g = draft.macrosPer100Grams.fatGrams
        fiberGramsPer100g = draft.macrosPer100Grams.fiberGrams
        energyKilocaloriesPer100g = draft.macrosPer100Grams.energyKilocalories
    }

    var category: FoodCategory {
        FoodCategory(rawValue: categoryRawValue) ?? .other
    }

    var portionSource: PortionEstimate.Source {
        PortionEstimate.Source(rawValue: portionSourceRawValue) ?? .visualEstimate
    }

    var macrosPer100Grams: MacroNutrients {
        MacroNutrients(
            proteinGrams: proteinGramsPer100g,
            carbohydrateGrams: carbohydrateGramsPer100g,
            fatGrams: fatGramsPer100g,
            fiberGrams: fiberGramsPer100g,
            energyKilocalories: energyKilocaloriesPer100g
        )
    }

    var totalMacros: MacroNutrients {
        macrosPer100Grams.forPortion(grams: grams)
    }
}
