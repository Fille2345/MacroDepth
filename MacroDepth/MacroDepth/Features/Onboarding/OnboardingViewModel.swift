// Features/Onboarding/OnboardingViewModel.swift

import Foundation
import Observation

/// Drives the goal → stats → review flow, for first launch and for later edits.
@MainActor
@Observable
final class OnboardingViewModel: Identifiable {
    enum Step: Int, CaseIterable {
        case goal
        case stats
        case review
    }

    static let calorieStep = 50.0
    static let macroStep = 5.0

    private(set) var step: Step = .goal
    private(set) var saveError: ErrorPresentation?
    private(set) var overrides: TargetOverrides = .none

    var goal: FitnessGoal?
    var weightText = ""
    var heightText = ""
    var ageText = ""
    var biologicalSex: BiologicalSex?
    var activityLevel: ActivityLevel?

    let isEditing: Bool

    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let now: Date
    @ObservationIgnored private let calendar: Calendar

    init(
        persistence: any PersistenceServiceProtocol,
        existingProfile: UserProfileDraft? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.persistence = persistence
        self.now = now
        self.calendar = calendar
        isEditing = existingProfile != nil

        if let existingProfile {
            goal = existingProfile.goal
            weightText = existingProfile.weightKg.formatted(.number.grouping(.never))
            heightText = existingProfile.heightCm.formatted(.number.grouping(.never))
            ageText = String(existingProfile.age(on: now, calendar: calendar))
            biologicalSex = existingProfile.biologicalSex
            activityLevel = existingProfile.activityLevel
            overrides = existingProfile.overrides
        }
    }

    // MARK: Parsed input

    var weightKg: Double? { Self.parse(weightText).flatMap { UserProfileDraft.weightRange.contains($0) ? $0 : nil } }
    var heightCm: Double? { Self.parse(heightText).flatMap { UserProfileDraft.heightRange.contains($0) ? $0 : nil } }
    var age: Int? { Int(ageText.trimmingCharacters(in: .whitespaces)).flatMap { UserProfileDraft.ageRange.contains($0) ? $0 : nil } }

    /// Accepts "72.5" and "72,5", whatever the device's locale.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    var weightError: String? {
        guard !weightText.isEmpty, weightKg == nil else { return nil }
        return "Enter a weight from \(Int(UserProfileDraft.weightRange.lowerBound)) to \(Int(UserProfileDraft.weightRange.upperBound)) kg."
    }

    var heightError: String? {
        guard !heightText.isEmpty, heightCm == nil else { return nil }
        return "Enter a height from \(Int(UserProfileDraft.heightRange.lowerBound)) to \(Int(UserProfileDraft.heightRange.upperBound)) cm."
    }

    var ageError: String? {
        guard !ageText.isEmpty, age == nil else { return nil }
        return "MacroDepth's targets are for adults aged \(UserProfileDraft.ageRange.lowerBound) to \(UserProfileDraft.ageRange.upperBound)."
    }

    /// The profile as currently entered, or `nil` while anything is missing or invalid.
    var draft: UserProfileDraft? {
        guard let goal, let weightKg, let heightCm, let age, let biologicalSex, let activityLevel else { return nil }
        return UserProfileDraft(
            weightKg: weightKg,
            heightCm: heightCm,
            birthYear: calendar.component(.year, from: now) - age,
            biologicalSex: biologicalSex,
            activityLevel: activityLevel,
            goal: goal,
            overrides: overrides
        )
    }

    var targets: NutritionTargets? { draft?.targets(on: now, calendar: calendar) }

    // MARK: Navigation

    var canAdvance: Bool {
        switch step {
        case .goal: goal != nil
        case .stats, .review: draft != nil
        }
    }

    var canGoBack: Bool { step != .goal }

    func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        saveError = nil
        step = previous
    }

    // MARK: Tweaks

    var hasOverrides: Bool { !overrides.isEmpty }

    func adjustCalories(by delta: Double) {
        guard let targets else { return }
        overrides.calories = targets.calories + delta
        normalizeOverrides()
    }

    func adjustProtein(by delta: Double) {
        guard let targets else { return }
        overrides.proteinGrams = targets.proteinGrams + delta
        normalizeOverrides()
    }

    func adjustCarbohydrate(by delta: Double) {
        guard let targets else { return }
        overrides.carbohydrateGrams = targets.carbohydrateGrams + delta
        normalizeOverrides()
    }

    func adjustFat(by delta: Double) {
        guard let targets else { return }
        overrides.fatGrams = targets.fatGrams + delta
        normalizeOverrides()
    }

    func resetOverrides() {
        overrides = .none
    }

    /// Stores overrides as the clamped values, so the steppers stop at the limits
    /// instead of silently accumulating past them.
    private func normalizeOverrides() {
        guard let biologicalSex else { return }
        overrides.calories = overrides.calories.map { Self.clamp($0, to: TargetLimits.calories(for: biologicalSex)) }
        overrides.proteinGrams = overrides.proteinGrams.map { Self.clamp($0, to: TargetLimits.protein) }
        overrides.carbohydrateGrams = overrides.carbohydrateGrams.map { Self.clamp($0, to: TargetLimits.carbohydrate) }
        overrides.fatGrams = overrides.fatGrams.map { Self.clamp($0, to: TargetLimits.fat) }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Saving

    /// Returns `true` once the profile is stored.
    func save() -> Bool {
        guard let draft else { return false }
        do {
            try persistence.saveProfile(draft)
            saveError = nil
            return true
        } catch {
            saveError = ErrorPresentation(error)
            return false
        }
    }
}
