// Domain/Nutrition/MacroNutrients.swift

import Foundation

/// Macronutrient quantities in grams plus energy in kilocalories.
///
/// The same type represents absolute totals (one logged item, a whole day) and
/// reference values per 100 g of food.
///
/// Carbohydrate convention: `carbohydrateGrams` is *available* carbohydrate
/// (fibre excluded), matching EU/Nordic labelling. Fibre is tracked separately
/// and contributes 2 kcal/g in the Atwater energy check.
struct MacroNutrients: Sendable, Hashable, Codable {
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var energyKilocalories: Double

    static let zero = MacroNutrients(
        proteinGrams: 0,
        carbohydrateGrams: 0,
        fatGrams: 0,
        fiberGrams: 0,
        energyKilocalories: 0
    )

    /// Atwater general factors, kcal per gram.
    enum AtwaterFactor {
        static let protein = 4.0
        static let carbohydrate = 4.0
        static let fat = 9.0
        static let fiber = 2.0
    }

    /// - Parameter energyKilocalories: Stated energy. When `nil`, energy is derived
    ///   from the macronutrients using Atwater factors.
    init(
        proteinGrams: Double,
        carbohydrateGrams: Double,
        fatGrams: Double,
        fiberGrams: Double = 0,
        energyKilocalories: Double? = nil
    ) {
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.energyKilocalories = energyKilocalories ?? Self.atwaterEnergy(
            protein: proteinGrams,
            carbohydrate: carbohydrateGrams,
            fat: fatGrams,
            fiber: fiberGrams
        )
    }

    static func atwaterEnergy(protein: Double, carbohydrate: Double, fat: Double, fiber: Double) -> Double {
        protein * AtwaterFactor.protein
            + carbohydrate * AtwaterFactor.carbohydrate
            + fat * AtwaterFactor.fat
            + fiber * AtwaterFactor.fiber
    }

    /// Energy implied by the macronutrients alone.
    var atwaterEnergyKilocalories: Double {
        Self.atwaterEnergy(protein: proteinGrams, carbohydrate: carbohydrateGrams, fat: fatGrams, fiber: fiberGrams)
    }

    /// Relative difference between stated and Atwater energy (0 means identical).
    var energyDiscrepancy: Double {
        let reference = max(atwaterEnergyKilocalories, 1)
        return abs(energyKilocalories - atwaterEnergyKilocalories) / reference
    }

    func isEnergyConsistent(tolerance: Double = 0.2) -> Bool {
        energyDiscrepancy <= tolerance
    }

    /// Returns a copy whose energy is replaced by the Atwater value when the stated
    /// energy disagrees with the macros by more than `tolerance`. Model output
    /// occasionally gets one of the two wrong; macros are the more reliable signal.
    func reconcilingEnergy(tolerance: Double = 0.2) -> MacroNutrients {
        guard !isEnergyConsistent(tolerance: tolerance) else { return self }
        var copy = self
        copy.energyKilocalories = atwaterEnergyKilocalories
        return copy
    }

    /// All values finite and non-negative.
    var isValid: Bool {
        [proteinGrams, carbohydrateGrams, fatGrams, fiberGrams, energyKilocalories]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }

    /// Combined mass of the macronutrients. For a per-100 g reference this cannot
    /// meaningfully exceed 100 g.
    var macronutrientMassGrams: Double {
        proteinGrams + carbohydrateGrams + fatGrams + fiberGrams
    }

    func scaled(by factor: Double) -> MacroNutrients {
        MacroNutrients(
            proteinGrams: proteinGrams * factor,
            carbohydrateGrams: carbohydrateGrams * factor,
            fatGrams: fatGrams * factor,
            fiberGrams: fiberGrams * factor,
            energyKilocalories: energyKilocalories * factor
        )
    }

    /// Absolute macros for `grams` of a food described by per-100 g values.
    func forPortion(grams: Double) -> MacroNutrients {
        scaled(by: grams / 100)
    }

    static func + (lhs: MacroNutrients, rhs: MacroNutrients) -> MacroNutrients {
        MacroNutrients(
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            fiberGrams: lhs.fiberGrams + rhs.fiberGrams,
            energyKilocalories: lhs.energyKilocalories + rhs.energyKilocalories
        )
    }

    static func += (lhs: inout MacroNutrients, rhs: MacroNutrients) {
        lhs = lhs + rhs
    }
}

extension Sequence where Element == MacroNutrients {
    func sum() -> MacroNutrients {
        reduce(.zero, +)
    }
}
