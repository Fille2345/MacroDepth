// MacroDepthTests/MacroNutrientsTests.swift

import Testing
@testable import MacroDepth

struct MacroNutrientsTests {
    @Test func derivesEnergyFromAtwaterFactors() {
        let macros = MacroNutrients(proteinGrams: 10, carbohydrateGrams: 20, fatGrams: 5, fiberGrams: 4)
        // 10·4 + 20·4 + 5·9 + 4·2 = 173
        #expect(macros.energyKilocalories == 173)
        #expect(macros.energyDiscrepancy == 0)
    }

    @Test func scalesPerHundredGramsToPortion() {
        let per100 = MacroNutrients(proteinGrams: 31, carbohydrateGrams: 0, fatGrams: 3.6, energyKilocalories: 165)
        let portion = per100.forPortion(grams: 200)
        #expect(portion.proteinGrams == 62)
        #expect(portion.energyKilocalories == 330)
    }

    @Test func sumsSequences() {
        let a = MacroNutrients(proteinGrams: 1, carbohydrateGrams: 2, fatGrams: 3, fiberGrams: 4, energyKilocalories: 50)
        let total = [a, a, a].sum()
        #expect(total.proteinGrams == 3)
        #expect(total.fiberGrams == 12)
        #expect(total.energyKilocalories == 150)
        #expect([MacroNutrients]().sum() == .zero)
    }

    @Test func reconcilesInconsistentEnergy() {
        let wrong = MacroNutrients(proteinGrams: 10, carbohydrateGrams: 10, fatGrams: 10, energyKilocalories: 500)
        #expect(!wrong.isEnergyConsistent())
        let fixed = wrong.reconcilingEnergy()
        #expect(fixed.energyKilocalories == 170)

        let close = MacroNutrients(proteinGrams: 10, carbohydrateGrams: 10, fatGrams: 10, energyKilocalories: 180)
        #expect(close.reconcilingEnergy() == close)
    }

    @Test func detectsInvalidValues() {
        #expect(!MacroNutrients(proteinGrams: -1, carbohydrateGrams: 0, fatGrams: 0).isValid)
        #expect(!MacroNutrients(proteinGrams: .nan, carbohydrateGrams: 0, fatGrams: 0).isValid)
        #expect(MacroNutrients(proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0).isValid)
    }

    @Test func sampleReferenceDataIsEnergyConsistent() {
        for food in SampleScene.foods {
            #expect(food.macrosPer100Grams.isEnergyConsistent(), "\(food.label)")
            #expect(food.macrosPer100Grams.macronutrientMassGrams <= 100, "\(food.label)")
        }
    }
}
