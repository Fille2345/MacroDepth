// Features/Recipes/RecipeSuggestion.swift

import Foundation

/// One serving of a built-in recipe. Macros are estimates from typical nutrition values.
struct RecipeSuggestion: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let mealType: MealType
    let targetGoal: FitnessGoal
    let estimatedCalories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let ingredientsList: [String]
    let preparationInstructions: [String]

    /// Text for the scanner's notes. "Serves 1" matters: the Gemini prompt otherwise
    /// treats recipe quantities as covering a whole multi-serving recipe.
    var scanNotes: String {
        """
        Recipe: \(title) (serves 1)

        Ingredients:
        \(ingredientsList.map { "- \($0)" }.joined(separator: "\n"))

        Preparation:
        \(preparationInstructions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
    }

    var proteinPer100Calories: Double {
        estimatedCalories > 0 ? proteinG / estimatedCalories * 100 : 0
    }
}

enum RecipeRecommender {
    /// Recipes for a goal, optionally for one meal type. Those that fit the calories
    /// left today come first, then those with the most protein per calorie.
    static func recommend(
        from catalog: [RecipeSuggestion] = RecipeCatalog.all,
        goal: FitnessGoal,
        mealType: MealType? = nil,
        remainingCalories: Double? = nil
    ) -> [RecipeSuggestion] {
        catalog
            .filter { $0.targetGoal == goal && (mealType == nil || $0.mealType == mealType) }
            .sorted { lhs, rhs in
                let lhsFits = fits(lhs, remainingCalories: remainingCalories)
                let rhsFits = fits(rhs, remainingCalories: remainingCalories)
                if lhsFits != rhsFits { return lhsFits }
                if lhs.proteinPer100Calories != rhs.proteinPer100Calories {
                    return lhs.proteinPer100Calories > rhs.proteinPer100Calories
                }
                return lhs.title < rhs.title
            }
    }

    static func fits(_ recipe: RecipeSuggestion, remainingCalories: Double?) -> Bool {
        guard let remainingCalories else { return true }
        return recipe.estimatedCalories <= remainingCalories
    }
}
