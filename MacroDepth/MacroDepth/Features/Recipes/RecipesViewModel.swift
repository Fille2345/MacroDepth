// Features/Recipes/RecipesViewModel.swift

import Foundation
import Observation

@MainActor
@Observable
final class RecipesViewModel {
    /// Follows the profile's goal until the user picks another one here.
    var selectedGoal: FitnessGoal {
        get { chosenGoal ?? profileGoal ?? .leanBulk }
        set { chosenGoal = newValue }
    }
    var selectedMealType: MealType?

    private(set) var remainingCalories: Double?
    private(set) var errorPresentation: ErrorPresentation?

    private var chosenGoal: FitnessGoal?
    private var profileGoal: FitnessGoal?

    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let now: @MainActor () -> Date

    init(persistence: any PersistenceServiceProtocol, now: @escaping @MainActor () -> Date = { .now }) {
        self.persistence = persistence
        self.now = now
    }

    var recipes: [RecipeSuggestion] {
        RecipeRecommender.recommend(
            goal: selectedGoal,
            mealType: selectedMealType,
            remainingCalories: remainingCalories
        )
    }

    func fitsToday(_ recipe: RecipeSuggestion) -> Bool {
        RecipeRecommender.fits(recipe, remainingCalories: remainingCalories)
    }

    func load() {
        do {
            let profile = try persistence.currentProfile()
            profileGoal = profile?.goal
            if let profile {
                let date = now()
                let eaten = try persistence.meals(on: date).map(\.totalMacros).sum()
                remainingCalories = DailyProgress(targets: profile.targets(on: date), eaten: eaten).remainingCalories
            } else {
                remainingCalories = nil
            }
            errorPresentation = nil
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    /// Call from the view's `.task`.
    func observeChanges() async {
        load()
        for await _ in persistence.changes() {
            load()
        }
    }
}
