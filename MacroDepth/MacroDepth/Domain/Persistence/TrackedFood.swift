// Domain/Persistence/TrackedFood.swift

import Foundation
import SwiftData

/// A food the user found by search or barcode, remembered for quick re-logging.
/// It keeps a snapshot of the product, so it works offline and survives the
/// database changing or removing it.
@Model
final class TrackedFood {
    /// `FoodProduct.id`, such as a barcode or a catalog id.
    @Attribute(.unique) var productID: String
    var name: String
    var brand: String?
    var categoryRawValue: String
    var barcode: String?
    var isGeneric: Bool
    var typicalServingGrams: Double

    var proteinGramsPer100g: Double
    var carbohydrateGramsPer100g: Double
    var fatGramsPer100g: Double
    var fiberGramsPer100g: Double
    var energyKilocaloriesPer100g: Double

    /// The weight added last time, suggested next time.
    var lastGrams: Double
    /// `nil` for a favorite that hasn't been added to a meal yet.
    var lastUsedAt: Date?
    var useCount: Int
    var isFavorite: Bool

    init(product: FoodProduct) {
        productID = product.id
        name = product.name
        categoryRawValue = product.category.rawValue
        isGeneric = product.isGeneric
        typicalServingGrams = product.typicalServingGrams
        proteinGramsPer100g = 0
        carbohydrateGramsPer100g = 0
        fatGramsPer100g = 0
        fiberGramsPer100g = 0
        energyKilocaloriesPer100g = 0
        lastGrams = product.typicalServingGrams
        useCount = 0
        isFavorite = false
        update(from: product)
    }

    /// Takes the product's current values, which a database may have corrected.
    func update(from product: FoodProduct) {
        name = product.name
        brand = product.brand
        categoryRawValue = product.category.rawValue
        barcode = product.barcode
        isGeneric = product.isGeneric
        typicalServingGrams = product.typicalServingGrams
        proteinGramsPer100g = product.macrosPer100Grams.proteinGrams
        carbohydrateGramsPer100g = product.macrosPer100Grams.carbohydrateGrams
        fatGramsPer100g = product.macrosPer100Grams.fatGrams
        fiberGramsPer100g = product.macrosPer100Grams.fiberGrams
        energyKilocaloriesPer100g = product.macrosPer100Grams.energyKilocalories
    }

    var remembered: RememberedFood {
        RememberedFood(
            product: FoodProduct(
                id: productID,
                name: name,
                brand: brand,
                category: FoodCategory(rawValue: categoryRawValue) ?? .other,
                macrosPer100Grams: MacroNutrients(
                    proteinGrams: proteinGramsPer100g,
                    carbohydrateGrams: carbohydrateGramsPer100g,
                    fatGrams: fatGramsPer100g,
                    fiberGrams: fiberGramsPer100g,
                    energyKilocalories: energyKilocaloriesPer100g
                ),
                typicalServingGrams: typicalServingGrams,
                barcode: barcode,
                isGeneric: isGeneric
            ),
            lastGrams: lastGrams,
            isFavorite: isFavorite
        )
    }
}

/// A remembered food as a value, for view models.
struct RememberedFood: Identifiable, Hashable, Sendable {
    let product: FoodProduct
    let lastGrams: Double
    let isFavorite: Bool

    var id: String { product.id }
}

struct RememberedFoods: Equatable, Sendable {
    /// Alphabetical.
    var favorites: [RememberedFood] = []
    /// Most recent first, favorites left out.
    var recents: [RememberedFood] = []
}
