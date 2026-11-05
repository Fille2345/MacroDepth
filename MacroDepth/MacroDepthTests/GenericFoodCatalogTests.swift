// MacroDepthTests/GenericFoodCatalogTests.swift

import Foundation
import Testing
@testable import MacroDepth

struct GenericFoodCatalogTests {
    private func ids(_ query: String) -> [String] {
        GenericFoodCatalog.search(query).map(\.id)
    }

    // MARK: Search

    /// English and Swedish names find the same food, with or without accents.
    @Test(arguments: [
        ("Banana", "generic-banana"), ("Banan", "generic-banana"), ("BANAN", "generic-banana"),
        ("Apple", "generic-apple"), ("äpple", "generic-apple"), ("apple", "generic-apple"), ("Äpple", "generic-apple"),
        ("Chicken", "generic-chicken-breast-raw"), ("Kyckling", "generic-chicken-breast-raw"),
        ("kycklingbröst", "generic-chicken-breast-raw"),
        ("Egg", "generic-egg-raw"), ("ägg", "generic-egg-raw"), ("agg", "generic-egg-raw"),
        ("White rice", "generic-white-rice-cooked"), ("ris", "generic-white-rice-cooked"),
        ("Potato", "generic-potato"), ("Potatis", "generic-potato"),
        ("Oats", "generic-oats"), ("Havregryn", "generic-oats"),
        ("Salmon", "generic-salmon-raw"), ("Lax", "generic-salmon-raw"),
        ("Beef", "generic-beef-mince-raw"), ("Nötfärs", "generic-beef-mince-raw"), ("köttfärs", "generic-beef-mince-raw"),
        ("Milk", "generic-whole-milk"), ("Mjölk", "generic-whole-milk"),
        ("Cheese", "generic-cottage-cheese"), ("Ost", "generic-cottage-cheese"),
        ("Keso", "generic-cottage-cheese"), ("Tonfisk", "generic-tuna"),
    ])
    func findsTheFoodInEitherLanguage(query: String, expected: String) {
        #expect(ids(query).first == expected, "\(query) found \(ids(query))")
    }

    @Test func wordsCanComeInAnyOrderAndAllMustMatch() {
        #expect(ids("cooked chicken") == ["generic-chicken-breast-cooked"])
        #expect(ids("kyckling tillagad") == ["generic-chicken-breast-cooked"])
        #expect(ids("rå lax") == ["generic-salmon-raw"])
        #expect(ids("chicken banana").isEmpty)
    }

    /// Matching only word starts stops short queries finding unrelated foods.
    @Test func matchesWordStartsNotTheMiddleOfWords() {
        let results = GenericFoodCatalog.search("ris")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .grainOrStarch })
        #expect(ids("nana").isEmpty)
        #expect(ids("kling").isEmpty)
    }

    @Test func anExactWordOutranksAWordItOnlyStarts() {
        // "oil" is an exact tag for olive oil.
        #expect(ids("oil").first == "generic-olive-oil")
        // "ost" is an exact word for cheeses, whatever else starts with it.
        let cheeseIDs = ids("ost").prefix(2)
        #expect(cheeseIDs.allSatisfy { $0.contains("cheese") || $0.contains("cheddar") })
    }

    @Test(arguments: ["", "   ", "\n", "zzzz", "!!!"])
    func emptyOrUnknownQueriesFindNothing(query: String) {
        #expect(ids(query).isEmpty)
    }

    // MARK: Contents

    @Test func hasTheAskedForRangeOfFoods() {
        #expect((30...60).contains(GenericFoodCatalog.foods.count))
        #expect(Set(GenericFoodCatalog.foods.map(\.id)).count == GenericFoodCatalog.foods.count)
        #expect(GenericFoodCatalog.foods.allSatisfy { $0.isGeneric })
        #expect(GenericFoodCatalog.foods.allSatisfy { $0.barcode == nil && $0.brand == nil })
    }

    @Test func everyFoodIsValidAndPossible() {
        for food in GenericFoodCatalog.foods {
            let macros = food.macrosPer100Grams
            #expect(macros.isValid, "\(food.name)")
            #expect(macros.macronutrientMassGrams <= 100.5, "\(food.name): \(macros.macronutrientMassGrams) g")
            #expect(PortionCalculator.manualEntryRange.contains(food.typicalServingGrams), "\(food.name)")
        }
    }

    /// USDA's energy uses food-specific factors, so it's not identical to the Atwater value,
    /// but a large gap would mean a mistyped or swapped value. Very low-energy foods get
    /// an absolute margin, because small differences are large percentages for them.
    @Test func energyAgreesWithTheMacros() {
        for food in GenericFoodCatalog.foods {
            let macros = food.macrosPer100Grams
            let gap = abs(macros.energyKilocalories - macros.atwaterEnergyKilocalories)
            #expect(gap <= max(macros.energyKilocalories * 0.15, 12), "\(food.name): \(macros.energyKilocalories) vs \(macros.atwaterEnergyKilocalories)")
        }
    }

    /// Checked by hand against USDA FoodData Central, so an accidental edit or a bad
    /// regeneration of the catalog can't pass unnoticed.
    @Test(arguments: [
        ("generic-banana", 89.0, 1.09, 0.33),
        ("generic-chicken-breast-raw", 120.0, 22.5, 2.62),
        ("generic-chicken-breast-cooked", 165.0, 31.02, 3.57),
        ("generic-egg-boiled", 155.0, 12.58, 10.61),
        ("generic-white-rice-cooked", 130.0, 2.69, 0.28),
        ("generic-olive-oil", 884.0, 0.0, 100.0),
    ])
    func keyValuesMatchTheSource(id: String, kcal: Double, protein: Double, fat: Double) throws {
        let food = try #require(GenericFoodCatalog.foods.first { $0.id == id })
        #expect(food.macrosPer100Grams.energyKilocalories == kcal)
        #expect(food.macrosPer100Grams.proteinGrams == protein)
        #expect(food.macrosPer100Grams.fatGrams == fat)
    }

    /// The app counts carbs without fibre, so a banana's 22.84 g total becomes 20.24 g.
    @Test func carbsExcludeFibre() throws {
        let banana = try #require(GenericFoodCatalog.foods.first { $0.id == "generic-banana" })
        #expect(banana.macrosPer100Grams.carbohydrateGrams == 20.24)
        #expect(banana.macrosPer100Grams.fiberGrams == 2.6)
    }
}
