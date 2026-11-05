// Services/FoodLookup/MockFoodLookupService.swift

import Foundation

/// Stand-in for a food database. Its results are labelled as sample data in the UI.
struct MockFoodLookupService: FoodLookupServiceProtocol {
    enum Behavior: Sendable, Equatable {
        case success
        case failure(FoodLookupError)
    }

    /// This code reports "not found", so that path can be tried on a device.
    static let unknownBarcode = "0000000000000"

    /// Typical values per 100 g, written by hand as sample data.
    static let catalog: [FoodProduct] = [
        food("Chicken breast, cooked", .meat, protein: 31, carbs: 0, fat: 3.6, fiber: 0, kcal: 165, serving: 150),
        food("Salmon, baked", .fish, protein: 25, carbs: 0, fat: 13, fiber: 0, kcal: 217, serving: 140),
        food("Beef mince, 10% fat, cooked", .meat, protein: 26, carbs: 0, fat: 11, fiber: 0, kcal: 205, serving: 125),
        food("Egg, boiled", .egg, protein: 13, carbs: 1.1, fat: 11, fiber: 0, kcal: 155, serving: 55),
        food("Tofu, firm", .legume, protein: 15, carbs: 2, fat: 8.5, fiber: 1.5, kcal: 145, serving: 125),
        food("Lentils, cooked", .legume, protein: 9, carbs: 16, fat: 0.4, fiber: 8, kcal: 116, serving: 180),
        food("White rice, cooked", .grainOrStarch, protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4, kcal: 130, serving: 180),
        food("Pasta, cooked", .grainOrStarch, protein: 5.8, carbs: 30, fat: 0.9, fiber: 1.8, kcal: 158, serving: 200),
        food("Potato, boiled", .grainOrStarch, protein: 2, carbs: 18, fat: 0.1, fiber: 1.8, kcal: 87, serving: 200),
        food("Oats, dry", .grainOrStarch, protein: 13, carbs: 58, fat: 7, fiber: 10, kcal: 380, serving: 50),
        food("Wholegrain bread", .bakedGood, protein: 10, carbs: 40, fat: 3.5, fiber: 7, kcal: 245, serving: 40),
        food("Banana", .fruit, protein: 1.1, carbs: 20, fat: 0.3, fiber: 2.6, kcal: 90, serving: 120),
        food("Apple", .fruit, protein: 0.3, carbs: 12, fat: 0.2, fiber: 2.4, kcal: 54, serving: 180),
        food("Broccoli, steamed", .vegetable, protein: 2.4, carbs: 3.9, fat: 0.4, fiber: 3.3, kcal: 35, serving: 100),
        food("Mixed salad leaves", .leafyVegetable, protein: 1.5, carbs: 1.5, fat: 0.3, fiber: 1.8, kcal: 17, serving: 60),
        food("Greek yogurt, plain", .dairy, protein: 9, carbs: 4, fat: 5, fiber: 0, kcal: 97, serving: 170),
        food("Milk, semi-skimmed", .dairy, protein: 3.5, carbs: 4.8, fat: 1.7, fiber: 0, kcal: 49, serving: 250),
        food("Cheddar cheese", .cheese, protein: 25, carbs: 1.3, fat: 33, fiber: 0, kcal: 403, serving: 30),
        food("Almonds", .nutsOrSeeds, protein: 21, carbs: 10, fat: 50, fiber: 12, kcal: 600, serving: 30),
        food("Olive oil", .sauceOrDressing, protein: 0, carbs: 0, fat: 100, fiber: 0, kcal: 884, serving: 10),
    ]

    let behavior: Behavior
    let latency: Duration

    init(behavior: Behavior = .success, latency: Duration = .milliseconds(300)) {
        self.behavior = behavior
        self.latency = latency
    }

    func product(forBarcode barcode: String) async throws -> FoodProduct? {
        try await Task.sleep(for: latency)
        if case .failure(let error) = behavior { throw error }
        guard barcode != Self.unknownBarcode else { return nil }
        return FoodProduct(
            id: barcode,
            name: "Sample product \(barcode)",
            brand: "Sample data",
            category: .other,
            macrosPer100Grams: MacroNutrients(proteinGrams: 10, carbohydrateGrams: 50, fatGrams: 15, fiberGrams: 3, energyKilocalories: 381),
            typicalServingGrams: 50,
            barcode: barcode
        )
    }

    func searchFoods(matching query: String) async throws -> [FoodProduct] {
        try await Task.sleep(for: latency)
        if case .failure(let error) = behavior { throw error }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let matches = Self.catalog.filter { food in
            terms.allSatisfy { food.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        // Names starting with the query rank above names that only contain it.
        return matches.sorted { first, second in
            let firstLeads = first.name.lowercased().hasPrefix(terms[0].lowercased())
            let secondLeads = second.name.lowercased().hasPrefix(terms[0].lowercased())
            return firstLeads == secondLeads ? first.name < second.name : firstLeads
        }
    }

    private static func food(
        _ name: String,
        _ category: FoodCategory,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        kcal: Double,
        serving: Double
    ) -> FoodProduct {
        FoodProduct(
            id: name,
            name: name,
            category: category,
            macrosPer100Grams: MacroNutrients(proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat, fiberGrams: fiber, energyKilocalories: kcal),
            typicalServingGrams: serving
        )
    }
}
