// Domain/Profile/UserProfile.swift

import Foundation
import SwiftData

/// The user's stats and goal as a `Sendable` value. Everything outside the
/// persistence service works with this rather than the `@Model` below.
struct UserProfileDraft: Sendable, Hashable {
    static let weightRange = 30.0...300.0
    static let heightRange = 100.0...250.0
    /// The equations and calorie guidance used here are for adults.
    static let ageRange = 18...100
    static let underweightBodyMassIndex = 18.5

    var weightKg: Double
    var heightCm: Double
    var birthYear: Int
    var biologicalSex: BiologicalSex
    var activityLevel: ActivityLevel
    var goal: FitnessGoal
    var overrides: TargetOverrides = .none

    var bodyMassIndex: Double {
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    /// A deficit isn't advisable here, so the review step warns about it.
    var isUnderweightForFatLoss: Bool {
        goal == .fatLoss && bodyMassIndex < Self.underweightBodyMassIndex
    }

    func isValid(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        Self.weightRange.contains(weightKg)
            && Self.heightRange.contains(heightCm)
            && Self.ageRange.contains(age(on: date, calendar: calendar))
    }
}

/// The single stored profile. Enums are stored as raw strings, like `MealEntry`.
@Model
final class UserProfile {
    var weightKg: Double
    var heightCm: Double
    var birthYear: Int
    var biologicalSexRawValue: String
    var activityLevelRawValue: String
    var goalRawValue: String
    var calorieOverride: Double?
    var proteinOverride: Double?
    var carbohydrateOverride: Double?
    var fatOverride: Double?
    var updatedAt: Date

    init(draft: UserProfileDraft, updatedAt: Date = .now) {
        weightKg = draft.weightKg
        heightCm = draft.heightCm
        birthYear = draft.birthYear
        biologicalSexRawValue = draft.biologicalSex.rawValue
        activityLevelRawValue = draft.activityLevel.rawValue
        goalRawValue = draft.goal.rawValue
        calorieOverride = draft.overrides.calories
        proteinOverride = draft.overrides.proteinGrams
        carbohydrateOverride = draft.overrides.carbohydrateGrams
        fatOverride = draft.overrides.fatGrams
        self.updatedAt = updatedAt
    }

    func update(from draft: UserProfileDraft, updatedAt: Date = .now) {
        weightKg = draft.weightKg
        heightCm = draft.heightCm
        birthYear = draft.birthYear
        biologicalSexRawValue = draft.biologicalSex.rawValue
        activityLevelRawValue = draft.activityLevel.rawValue
        goalRawValue = draft.goal.rawValue
        calorieOverride = draft.overrides.calories
        proteinOverride = draft.overrides.proteinGrams
        carbohydrateOverride = draft.overrides.carbohydrateGrams
        fatOverride = draft.overrides.fatGrams
        self.updatedAt = updatedAt
    }

    var draft: UserProfileDraft {
        UserProfileDraft(
            weightKg: weightKg,
            heightCm: heightCm,
            birthYear: birthYear,
            biologicalSex: BiologicalSex(rawValue: biologicalSexRawValue) ?? .female,
            activityLevel: ActivityLevel(rawValue: activityLevelRawValue) ?? .sedentary,
            goal: FitnessGoal(rawValue: goalRawValue) ?? .maintenance,
            overrides: TargetOverrides(
                calories: calorieOverride,
                proteinGrams: proteinOverride,
                carbohydrateGrams: carbohydrateOverride,
                fatGrams: fatOverride
            )
        )
    }
}
