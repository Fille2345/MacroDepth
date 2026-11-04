// Domain/Persistence/SavedMeal.swift

import Foundation
import SwiftData

/// A reusable meal template for the Recipe Book.
///
/// Totals are derived from the components rather than stored, so they can't drift.
/// Logging a template copies its components into a new `MealEntry`, so editing or
/// deleting the template never changes meals already logged.
@Model
final class SavedMeal {
    static let maximumNameLength = 100

    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    /// File name (not path) in the capture image directory. The template owns this
    /// file, so deleting the meal it came from can't remove it.
    var imageFileName: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavedMealComponent.savedMeal)
    var components: [SavedMealComponent] = []

    /// Meals logged from this template. Deleting the template only unlinks them.
    @Relationship(deleteRule: .nullify, inverse: \MealEntry.savedMeal)
    var loggedMeals: [MealEntry] = []

    init(id: UUID = UUID(), name: String, notes: String? = nil, imageFileName: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.notes = notes
        self.imageFileName = imageFileName
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Components in their original order (SwiftData relationships are unordered).
    var orderedComponents: [SavedMealComponent] {
        components.sorted { $0.sortIndex < $1.sortIndex }
    }

    var totalMacros: MacroNutrients {
        components.map(\.totalMacros).sum()
    }

    /// The trimmed name, or `nil` if it's blank or too long.
    static func validatedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumNameLength ? trimmed : nil
    }
}

/// One ingredient of a template, with the same per-100 g storage as `LoggedFoodItem`.
@Model
final class SavedMealComponent {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRawValue: String
    var sortIndex: Int

    var grams: Double
    var confidence: Double
    var volumeCubicCentimeters: Double?
    var densityGramsPerCubicCentimeter: Double?

    var proteinGramsPer100g: Double
    var carbohydrateGramsPer100g: Double
    var fatGramsPer100g: Double
    var fiberGramsPer100g: Double
    var energyKilocaloriesPer100g: Double

    var savedMeal: SavedMeal?

    init(draft: SavedMealComponentDraft, sortIndex: Int) {
        id = UUID()
        name = draft.name
        categoryRawValue = draft.category.rawValue
        self.sortIndex = sortIndex
        grams = draft.grams
        confidence = draft.confidence
        volumeCubicCentimeters = draft.volumeCubicCentimeters
        densityGramsPerCubicCentimeter = draft.densityGramsPerCubicCentimeter
        proteinGramsPer100g = draft.macrosPer100Grams.proteinGrams
        carbohydrateGramsPer100g = draft.macrosPer100Grams.carbohydrateGrams
        fatGramsPer100g = draft.macrosPer100Grams.fatGrams
        fiberGramsPer100g = draft.macrosPer100Grams.fiberGrams
        energyKilocaloriesPer100g = draft.macrosPer100Grams.energyKilocalories
    }

    var category: FoodCategory {
        FoodCategory(rawValue: categoryRawValue) ?? .other
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

/// Input for creating or editing a template. Like the other drafts, it's the
/// `Sendable` form that crosses the persistence boundary.
struct SavedMealDraft: Sendable, Hashable {
    var name: String
    var notes: String? = nil
    var components: [SavedMealComponentDraft]
    /// The template's photo. When editing, `nil` keeps the current photo.
    var imageJPEGData: Data? = nil

    var totalMacros: MacroNutrients {
        components.map { $0.macrosPer100Grams.forPortion(grams: $0.grams) }.sum()
    }
}

struct SavedMealComponentDraft: Sendable, Hashable {
    var name: String
    var category: FoodCategory
    var grams: Double
    var macrosPer100Grams: MacroNutrients
    var confidence: Double = 1
    var volumeCubicCentimeters: Double? = nil
    var densityGramsPerCubicCentimeter: Double? = nil

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && grams.isFinite && grams > 0 && macrosPer100Grams.isValid
    }
}

extension SavedMealComponentDraft {
    /// The item as it is now, including any weight the user corrected.
    init(item: LoggedFoodItem) {
        self.init(
            name: item.name,
            category: item.category,
            grams: item.grams,
            macrosPer100Grams: item.macrosPer100Grams,
            confidence: item.confidence,
            volumeCubicCentimeters: item.volumeCubicCentimeters,
            densityGramsPerCubicCentimeter: item.densityGramsPerCubicCentimeter
        )
    }
}
