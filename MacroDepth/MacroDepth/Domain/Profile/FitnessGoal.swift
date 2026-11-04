// Domain/Profile/FitnessGoal.swift

import Foundation

enum FitnessGoal: String, Sendable, Codable, CaseIterable, Identifiable {
    case leanBulk
    case fatLoss
    case maintenance

    var id: String { rawValue }

    /// Added to TDEE to get the daily calorie target.
    var calorieAdjustment: Double {
        switch self {
        case .leanBulk: 300
        case .fatLoss: -400
        case .maintenance: 0
        }
    }

    var proteinGramsPerKilogram: Double {
        switch self {
        case .leanBulk: 2.0
        case .fatLoss: 2.2
        case .maintenance: 1.8
        }
    }

    var displayName: String {
        switch self {
        case .leanBulk: "Build Lean Muscle (Lean Bulk)"
        case .fatLoss: "Lose Fat (Cut)"
        case .maintenance: "Maintain & Recomp"
        }
    }

    var shortName: String {
        switch self {
        case .leanBulk: "Lean Bulk"
        case .fatLoss: "Cut"
        case .maintenance: "Maintain"
        }
    }

    var summary: String {
        switch self {
        case .leanBulk: "A small calorie surplus with plenty of protein."
        case .fatLoss: "A moderate calorie deficit with extra protein to protect muscle."
        case .maintenance: "Eat at your baseline and improve body composition over time."
        }
    }

    var systemImage: String {
        switch self {
        case .leanBulk: "dumbbell"
        case .fatLoss: "flame"
        case .maintenance: "equal.circle"
        }
    }
}

/// The two values the Mifflin-St Jeor equation is defined for.
enum BiologicalSex: String, Sendable, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

enum ActivityLevel: String, Sendable, Codable, CaseIterable, Identifiable {
    case sedentary
    case moderate
    case veryActive

    var id: String { rawValue }

    /// Multiplier from BMR to TDEE.
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .moderate: 1.55
        case .veryActive: 1.725
        }
    }

    var displayName: String {
        switch self {
        case .sedentary: "Sedentary"
        case .moderate: "Moderate"
        case .veryActive: "Very active"
        }
    }

    var summary: String {
        switch self {
        case .sedentary: "Little or no planned exercise"
        case .moderate: "3–4 gym sessions a week"
        case .veryActive: "Hard training most days"
        }
    }
}
