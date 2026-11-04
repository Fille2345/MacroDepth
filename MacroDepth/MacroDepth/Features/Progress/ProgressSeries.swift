// Features/Progress/ProgressSeries.swift

import Foundation

enum ProgressRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var title: String { "\(rawValue) Days" }
}

struct DailyIntake: Identifiable, Hashable, Sendable {
    let day: Date
    let calories: Double
    let proteinGrams: Double

    var id: Date { day }
}

struct WeightPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let kilograms: Double

    var id: Date { date }
}

/// The calculations behind the Progress charts, kept free of SwiftUI and storage.
enum ProgressSeries {
    /// Daily weight swings with water and food, so the trend averages a week of weigh-ins.
    static let trendWindowDays = 7

    /// The last `range.days` calendar days, including all of today.
    static func interval(for range: ProgressRange, endingOn date: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: 1 - range.days, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// One value per day with meals, oldest first. A day with nothing logged has no
    /// value at all rather than zero, because it means "unknown", not "ate nothing".
    static func dailyIntake(from meals: [(timestamp: Date, macros: MacroNutrients)], calendar: Calendar) -> [DailyIntake] {
        Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }
            .map { day, meals in
                let total = meals.map(\.macros).sum()
                return DailyIntake(day: day, calories: total.energyKilocalories, proteinGrams: total.proteinGrams)
            }
            .sorted { $0.day < $1.day }
    }

    /// The trailing average at each point: the mean of all weigh-ins in the seven days
    /// ending on that date. `points` should start `trendWindowDays` before `visibleStart`
    /// so the line is already averaged at the left edge of the chart.
    static func trend(of points: [WeightPoint], visibleFrom visibleStart: Date, calendar: Calendar) -> [WeightPoint] {
        points.compactMap { point in
            guard point.date >= visibleStart,
                  let windowStart = calendar.date(byAdding: .day, value: 1 - trendWindowDays, to: point.date) else { return nil }
            let window = points.filter { $0.date >= windowStart && $0.date <= point.date }
            let mean = window.map(\.kilograms).reduce(0, +) / Double(window.count)
            return WeightPoint(date: point.date, kilograms: mean)
        }
    }

    /// Averages over finished days only: today is still in progress and would pull them down.
    static func averages(
        of intake: [DailyIntake],
        excludingDayOf date: Date,
        calendar: Calendar
    ) -> (calories: Double, proteinGrams: Double, dayCount: Int)? {
        let today = calendar.startOfDay(for: date)
        let finished = intake.filter { $0.day < today }
        guard !finished.isEmpty else { return nil }
        let count = Double(finished.count)
        return (
            finished.map(\.calories).reduce(0, +) / count,
            finished.map(\.proteinGrams).reduce(0, +) / count,
            finished.count
        )
    }
}
