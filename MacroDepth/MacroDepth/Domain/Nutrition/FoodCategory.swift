// Domain/Nutrition/FoodCategory.swift

import Foundation

/// Coarse food classes. They drive density bounds for volume → mass conversion
/// and are sent to Gemini as the allowed enum values in the response schema.
enum FoodCategory: String, Sendable, Codable, CaseIterable, Identifiable {
    case leafyVegetable
    case vegetable
    case fruit
    case grainOrStarch
    case legume
    case meat
    case fish
    case egg
    case dairy
    case cheese
    case sauceOrDressing
    case soupOrLiquid
    case bakedGood
    case dessert
    case nutsOrSeeds
    case mixedDish
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leafyVegetable: "Leafy greens"
        case .vegetable: "Vegetable"
        case .fruit: "Fruit"
        case .grainOrStarch: "Grain / starch"
        case .legume: "Legume"
        case .meat: "Meat"
        case .fish: "Fish & seafood"
        case .egg: "Egg"
        case .dairy: "Dairy"
        case .cheese: "Cheese"
        case .sauceOrDressing: "Sauce / dressing"
        case .soupOrLiquid: "Soup / liquid"
        case .bakedGood: "Bread / baked"
        case .dessert: "Dessert"
        case .nutsOrSeeds: "Nuts & seeds"
        case .mixedDish: "Mixed dish"
        case .other: "Other"
        }
    }

    /// Plausible *bulk* density in g/cm³.
    ///
    /// The LiDAR height field measures the volume under the visible top surface,
    /// air gaps included (a pile of broccoli or salad is mostly air). These are
    /// bulk densities, not material densities. They are heuristic bounds that will
    /// be calibrated against weighed reference meals; Gemini's suggested density
    /// is clamped into this range.
    var plausibleDensityRange: ClosedRange<Double> {
        switch self {
        case .leafyVegetable: 0.08...0.50
        case .vegetable: 0.25...1.00
        case .fruit: 0.50...1.05
        case .grainOrStarch: 0.45...1.10
        case .legume: 0.55...1.10
        case .meat: 0.80...1.15
        case .fish: 0.75...1.10
        case .egg: 0.70...1.10
        case .dairy: 0.90...1.15
        case .cheese: 0.85...1.25
        case .sauceOrDressing: 0.90...1.30
        case .soupOrLiquid: 0.95...1.10
        case .bakedGood: 0.15...0.75
        case .dessert: 0.35...1.25
        case .nutsOrSeeds: 0.40...0.80
        case .mixedDish: 0.45...1.10
        case .other: 0.20...1.30
        }
    }

    /// Fallback density (g/cm³) when no valid suggestion is available.
    var typicalDensity: Double {
        switch self {
        case .leafyVegetable: 0.25
        case .vegetable: 0.60
        case .fruit: 0.85
        case .grainOrStarch: 0.80
        case .legume: 0.85
        case .meat: 1.00
        case .fish: 0.95
        case .egg: 0.95
        case .dairy: 1.03
        case .cheese: 1.10
        case .sauceOrDressing: 1.05
        case .soupOrLiquid: 1.00
        case .bakedGood: 0.40
        case .dessert: 0.80
        case .nutsOrSeeds: 0.60
        case .mixedDish: 0.85
        case .other: 0.80
        }
    }
}
