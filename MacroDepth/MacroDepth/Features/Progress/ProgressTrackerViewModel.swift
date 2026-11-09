// Features/Progress/ProgressTrackerViewModel.swift

import Foundation
import Observation

/// Offers to use a newly logged weight for the profile's targets. Targets never change without a yes.
struct TargetUpdatePrompt: Equatable, Sendable {
    let updatedProfile: UserProfileDraft
    let message: String
}

@MainActor
@Observable
final class ProgressTrackerViewModel {
    /// Smaller differences are mostly water and food, not a change worth new targets.
    static let targetPromptThresholdKg = 1.0

    var selectedRange = ProgressRange.month {
        didSet { load() }
    }
    /// The date being touched on a chart, or `nil`.
    var selectedChartDate: Date?

    var weightText = ""
    var weightDate: Date

    private(set) var intake: [DailyIntake] = []
    /// Newest first, for the list of weigh-ins.
    private(set) var weightEntries: [WeightEntry] = []
    private(set) var weightPoints: [WeightPoint] = []
    private(set) var weightTrend: [WeightPoint] = []
    private(set) var targets: NutritionTargets?
    private(set) var chartDomain: ClosedRange<Date>
    private(set) var targetPrompt: TargetUpdatePrompt?
    private(set) var errorPresentation: ErrorPresentation?

    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date

    init(
        persistence: any PersistenceServiceProtocol,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
        let date = now()
        weightDate = date
        chartDomain = date...date
    }

    // MARK: Derived

    var latestDate: Date { now() }

    var parsedWeight: Double? {
        OnboardingViewModel.parse(weightText).flatMap { UserProfileDraft.weightRange.contains($0) ? $0 : nil }
    }

    var weightError: String? {
        guard !weightText.isEmpty, parsedWeight == nil else { return nil }
        return "Enter a weight from \(Int(UserProfileDraft.weightRange.lowerBound)) to \(Int(UserProfileDraft.weightRange.upperBound)) kg."
    }

    var averages: (calories: Double, proteinGrams: Double, dayCount: Int)? {
        ProgressSeries.averages(of: intake, excludingDayOf: now(), calendar: calendar)
    }

    /// Change in the trend across the range, which is steadier than first against last weigh-in.
    var weightChange: Double? {
        guard let first = weightTrend.first, let last = weightTrend.last, weightTrend.count >= 2 else { return nil }
        return last.kilograms - first.kilograms
    }

    /// A single point can't form a line, so the trend only appears from two weigh-ins.
    var showsTrendLine: Bool { weightTrend.count >= 2 }

    /// What was recorded on the day containing `date`, for the chart readout.
    func summary(for date: Date) -> (day: Date, intake: DailyIntake?, weight: WeightPoint?) {
        let day = calendar.startOfDay(for: date)
        return (
            day,
            intake.first { $0.day == day },
            weightPoints.first { calendar.isDate($0.date, inSameDayAs: day) }
        )
    }

    // MARK: Intents

    func load() {
        let date = now()
        guard let interval = ProgressSeries.interval(for: selectedRange, endingOn: date, calendar: calendar),
              let trendStart = calendar.date(byAdding: .day, value: 1 - ProgressSeries.trendWindowDays, to: interval.start) else { return }
        do {
            chartDomain = interval.start...interval.end
            intake = ProgressSeries.dailyIntake(
                from: try persistence.meals(in: interval).map { ($0.timestamp, $0.totalMacros) },
                calendar: calendar
            )

            // Fetched from a week earlier, so the trend is averaged from the chart's first day.
            let entries = try persistence.weightEntries(in: DateInterval(start: trendStart, end: interval.end))
            let allPoints = entries.map { WeightPoint(date: $0.date, kilograms: $0.weightKg) }
            weightTrend = ProgressSeries.trend(of: allPoints, visibleFrom: interval.start, calendar: calendar)
            weightPoints = allPoints.filter { $0.date >= interval.start }
            weightEntries = entries.filter { $0.date >= interval.start }.reversed()

            targets = try persistence.currentProfile()?.targets(on: date)
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

    func logWeight() {
        guard let kilograms = parsedWeight else { return }
        do {
            let entry = try persistence.saveWeight(kilograms: kilograms, on: weightDate)
            weightText = ""
            load()
            targetPrompt = try makeTargetPrompt(for: entry)
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    /// Weigh-ins from Apple Health are deleted there; deleting one here would only bring it back.
    func deleteWeight(_ entry: WeightEntry) {
        guard !entry.isFromHealth else { return }
        do {
            try persistence.deleteWeightEntry(entry)
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    func applyTargetUpdate(_ prompt: TargetUpdatePrompt) {
        targetPrompt = nil
        do {
            try persistence.saveProfile(prompt.updatedProfile)
            load()
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    func dismissTargetPrompt() {
        targetPrompt = nil
    }

    // MARK: Private

    /// Only the latest weigh-in describes current weight, so backfilling an old date doesn't ask.
    private func makeTargetPrompt(for entry: WeightEntry) throws -> TargetUpdatePrompt? {
        guard try persistence.latestWeightEntry()?.id == entry.id,
              let profile = try persistence.currentProfile(),
              // The small margin stops rounding from excluding a difference of exactly 1 kg.
              abs(profile.weightKg - entry.weightKg) + 1e-9 >= Self.targetPromptThresholdKg else { return nil }

        var updated = profile
        updated.weightKg = entry.weightKg
        let date = now()
        let current = profile.targets(on: date)
        let proposed = updated.targets(on: date)

        let weights = "Your profile says \(Self.kilograms(profile.weightKg)), and you just logged \(Self.kilograms(entry.weightKg))."
        let outcome: String
        if abs(current.calories - proposed.calories) < 1, abs(current.proteinGrams - proposed.proteinGrams) < 1 {
            outcome = "Your daily targets would stay at \(NutritionFormat.kilocalories(proposed.calories)) and \(NutritionFormat.grams(proposed.proteinGrams)) of protein."
        } else {
            outcome = "Your daily targets would change from \(NutritionFormat.kilocalories(current.calories)) and \(NutritionFormat.grams(current.proteinGrams)) of protein to \(NutritionFormat.kilocalories(proposed.calories)) and \(NutritionFormat.grams(proposed.proteinGrams))."
        }
        return TargetUpdatePrompt(updatedProfile: updated, message: "\(weights) \(outcome)")
    }

    private static func kilograms(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }
}
