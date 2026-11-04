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
    private(set) var savedMeals: [SavedMeal] = []
    /// Confirms the last "Log This Meal Today", so a second tap isn't made by mistake.
    private(set) var loggedConfirmation: String?
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

    func imageURL(for savedMeal: SavedMeal) -> URL? {
        persistence.imageURL(for: savedMeal)
    }

    func fitsToday(_ recipe: RecipeSuggestion) -> Bool {
        RecipeRecommender.fits(recipe, remainingCalories: remainingCalories)
    }

    func load() {
        do {
            savedMeals = try persistence.savedMeals()
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

    func logToday(_ savedMeal: SavedMeal) async {
        let name = savedMeal.name
        do {
            try await persistence.logSavedMeal(savedMeal, at: now(), mealType: nil)
            loggedConfirmation = "Logged \(name) for today."
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    func delete(_ savedMeal: SavedMeal) async {
        do {
            try await persistence.deleteSavedMeal(savedMeal)
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    func clearConfirmation() {
        loggedConfirmation = nil
    }

    /// Call from the view's `.task`.
    func observeChanges() async {
        load()
        for await _ in persistence.changes() {
            load()
        }
    }
}
