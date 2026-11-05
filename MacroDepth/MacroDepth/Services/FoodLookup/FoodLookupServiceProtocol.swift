// Services/FoodLookup/FoodLookupServiceProtocol.swift

import Foundation

/// Finds foods by barcode or name. The live app uses `OpenFoodFactsService`.
protocol FoodLookupServiceProtocol: Sendable {
    /// The product with this barcode, or `nil` if the database doesn't have it.
    func product(forBarcode barcode: String) async throws -> FoodProduct?

    /// Foods matching `query`, best match first.
    func searchFoods(matching query: String) async throws -> [FoodProduct]
}
