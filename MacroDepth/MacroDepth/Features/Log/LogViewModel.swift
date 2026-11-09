// Features/Log/LogViewModel.swift

import Foundation
import Observation

@MainActor
@Observable
final class LogViewModel {
    private(set) var selectedDay: Date
    private(set) var meals: [MealEntry] = []
    /// The day before `selectedDay`'s meals, offered for copying.
    private(set) var previousDayMeals: [MealEntry] = []
    private(set) var isCopying = false
    private(set) var errorPresentation: ErrorPresentation?
    /// Confirms the last "Save as Recipe".
    private(set) var savedConfirmation: String?

    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let calendar: Calendar

    init(persistence: any PersistenceServiceProtocol, calendar: Calendar = .current, initialDay: Date = .now) {
        self.persistence = persistence
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: initialDay)
    }

    var dayTotals: MacroNutrients { meals.map(\.totalMacros).sum() }

    var isShowingToday: Bool { calendar.isDateInToday(selectedDay) }

    var canGoForward: Bool { selectedDay < calendar.startOfDay(for: .now) }

    func load() {
        do {
            meals = try persistence.meals(on: selectedDay)
            previousDayMeals = try calendar.date(byAdding: .day, value: -1, to: selectedDay)
                .map { try persistence.meals(on: $0) } ?? []
            errorPresentation = nil
        } catch {
            meals = []
            previousDayMeals = []
            errorPresentation = ErrorPresentation(error)
        }
    }

    func goToPreviousDay() { shiftDay(by: -1) }

    func goToNextDay() {
        guard canGoForward else { return }
        shiftDay(by: 1)
    }

    func goToToday() {
        selectedDay = calendar.startOfDay(for: .now)
        load()
    }

    // MARK: Copy from the previous day

    var previousDayTitle: String {
        isShowingToday ? String(localized: "From Yesterday") : String(localized: "From the Day Before")
    }

    /// Whether `meal` from the previous day has already been copied to the selected day.
    func isCopied(_ meal: MealEntry) -> Bool {
        meals.contains { $0.copiedFromMealID == meal.id }
    }

    var uncopiedPreviousDayMeals: [MealEntry] {
        previousDayMeals.filter { !isCopied($0) }
    }

    /// Logs the meal again on the selected day, at the same time of day.
    func copy(_ meal: MealEntry) async {
        await copy([meal])
    }

    func copyAllFromPreviousDay() async {
        await copy(uncopiedPreviousDayMeals)
    }

    func delete(_ meal: MealEntry) async {
        do {
            try await persistence.deleteMeal(meal)
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    /// The meal's foods as a starting name, cut to the length a recipe name allows.
    func suggestedRecipeName(for meal: MealEntry) -> String {
        String(meal.orderedItems.map(\.name).formatted(.list(type: .and)).prefix(SavedMeal.maximumNameLength))
    }

    func saveAsRecipe(_ meal: MealEntry, name: String) async {
        do {
            let savedMeal = try await persistence.makeSavedMeal(from: meal, name: name)
            savedConfirmation = "Saved \(savedMeal.name) to your Recipe Book."
            errorPresentation = nil
        } catch {
            savedConfirmation = nil
            errorPresentation = ErrorPresentation(error)
        }
    }

    func clearConfirmation() {
        savedConfirmation = nil
    }

    func dismissError() {
        errorPresentation = nil
    }

    private func copy(_ sources: [MealEntry]) async {
        guard !isCopying, !sources.isEmpty else { return }
        isCopying = true
        defer { isCopying = false }
        do {
            for meal in sources where !isCopied(meal) {
                try await persistence.copyMeal(meal, to: selectedDay)
                load()
            }
            errorPresentation = nil
        } catch {
            load()
            errorPresentation = ErrorPresentation(error)
        }
    }

    private func shiftDay(by days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: day)
        load()
    }
}
