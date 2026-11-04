// Features/Log/LogViewModel.swift

import Foundation
import Observation

@MainActor
@Observable
final class LogViewModel {
    private(set) var selectedDay: Date
    private(set) var meals: [MealEntry] = []
    private(set) var errorPresentation: ErrorPresentation?

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
            errorPresentation = nil
        } catch {
            meals = []
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

    func delete(_ meal: MealEntry) async {
        do {
            try await persistence.deleteMeal(meal)
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    func dismissError() {
        errorPresentation = nil
    }

    private func shiftDay(by days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: day)
        load()
    }
}
