// Domain/Profile/NutritionTargets.swift

import Foundation

/// Optional manual values that replace calculated targets. They are always clamped
/// to `TargetLimits` when targets are computed, so a stored value can't produce an
/// unsafe target.
struct TargetOverrides: Sendable, Hashable, Codable {
    var calories: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?

    static let none = TargetOverrides()

    var isEmpty: Bool { self == .none }
}

/// Bounds for every daily target, calculated or manual.
enum TargetLimits {
    static let protein = 30.0...400.0
    static let carbohydrate = 0.0...1_000.0
    static let fat = 20.0...350.0

    /// The lower bounds are the commonly cited minimums for unsupervised dieting.
    static func calories(for sex: BiologicalSex) -> ClosedRange<Double> {
        switch sex {
        case .female: 1_200...6_000
        case .male: 1_500...6_000
        }
    }
}

/// Daily targets derived from a profile.
struct NutritionTargets: Sendable, Hashable {
    /// How far the macros' energy may differ from the calorie target before the user is warned.
    static let macroMismatchTolerance = 0.1
    /// Share of target calories allocated to fat when it isn't overridden.
    static let fatCalorieShare = 0.25

    let basalMetabolicRate: Double
    let totalDailyEnergyExpenditure: Double
    let calories: Double
    let proteinGrams: Double
    let carbohydrateGrams: Double
    let fatGrams: Double
    /// The goal's calculated target was below the minimum and was raised to it.
    let calorieFloorApplied: Bool

    /// Energy implied by the macro targets.
    var macroCalories: Double {
        MacroNutrients.atwaterEnergy(protein: proteinGrams, carbohydrate: carbohydrateGrams, fat: fatGrams, fiber: 0)
    }

    /// Manual values can describe macros that don't add up to the calorie target.
    var hasMacroMismatch: Bool {
        abs(macroCalories - calories) > calories * Self.macroMismatchTolerance
    }
}

extension UserProfileDraft {
    /// Mifflin-St Jeor: 10·kg + 6.25·cm − 5·age, then +5 (male) or −161 (female).
    func basalMetabolicRate(age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch biologicalSex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// Age from the birth year alone, so it can be up to a year high. That changes
    /// BMR by 5 kcal at most.
    func age(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date) - birthYear
    }

    func targets(on date: Date = .now, calendar: Calendar = .current) -> NutritionTargets {
        let bmr = basalMetabolicRate(age: age(on: date, calendar: calendar))
        let tdee = bmr * activityLevel.multiplier
        let calorieRange = TargetLimits.calories(for: biologicalSex)

        let calculatedCalories = tdee + goal.calorieAdjustment
        let calories = Self.resolve(overrides.calories, default: calculatedCalories, in: calorieRange)

        let protein = Self.resolve(
            overrides.proteinGrams,
            default: weightKg * goal.proteinGramsPerKilogram,
            in: TargetLimits.protein
        )
        let fat = Self.resolve(
            overrides.fatGrams,
            default: calories * NutritionTargets.fatCalorieShare / MacroNutrients.AtwaterFactor.fat,
            in: TargetLimits.fat
        )
        // Carbohydrate takes whatever energy protein and fat leave.
        let remainingCalories = calories
            - protein * MacroNutrients.AtwaterFactor.protein
            - fat * MacroNutrients.AtwaterFactor.fat
        let carbohydrate = Self.resolve(
            overrides.carbohydrateGrams,
            default: remainingCalories / MacroNutrients.AtwaterFactor.carbohydrate,
            in: TargetLimits.carbohydrate
        )

        return NutritionTargets(
            basalMetabolicRate: bmr,
            totalDailyEnergyExpenditure: tdee,
            calories: calories,
            proteinGrams: protein,
            carbohydrateGrams: carbohydrate,
            fatGrams: fat,
            calorieFloorApplied: overrides.calories == nil && calculatedCalories < calorieRange.lowerBound
        )
    }

    private static func resolve(_ override: Double?, default calculated: Double, in range: ClosedRange<Double>) -> Double {
        let value = override.flatMap { $0.isFinite ? $0 : nil } ?? calculated
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// A day's intake against its targets.
struct DailyProgress: Sendable, Hashable {
    let targets: NutritionTargets
    let eaten: MacroNutrients
    /// Calories burned through exercise. Stays 0 until the app has a source for it.
    var burnedCalories: Double = 0

    /// `Target − Eaten + Burned`. Negative when over target.
    var remainingCalories: Double {
        targets.calories - eaten.energyKilocalories + burnedCalories
    }

    var isOverTarget: Bool { remainingCalories < 0 }

    /// Share of the day's allowance used, in 0...1, for the ring.
    var calorieFraction: Double {
        Self.fraction(eaten.energyKilocalories, of: targets.calories + burnedCalories)
    }

    static func fraction(_ value: Double, of target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }
}
