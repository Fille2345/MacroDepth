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

    /// A copy of a template's component. The new id and stored values keep this
    /// item independent of later edits to the template.
    init(component: SavedMealComponent, sortIndex: Int) {
        id = UUID()
        name = component.name
        categoryRawValue = component.categoryRawValue
        self.sortIndex = sortIndex
        grams = component.grams
        portionSourceRawValue = PortionEstimate.Source.savedMeal.rawValue
        confidence = component.confidence
        volumeCubicCentimeters = component.volumeCubicCentimeters
        densityGramsPerCubicCentimeter = component.densityGramsPerCubicCentimeter
        proteinGramsPer100g = component.proteinGramsPer100g
        carbohydrateGramsPer100g = component.carbohydrateGramsPer100g
        fatGramsPer100g = component.fatGramsPer100g
        fiberGramsPer100g = component.fiberGramsPer100g
        energyKilocaloriesPer100g = component.energyKilocaloriesPer100g
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
