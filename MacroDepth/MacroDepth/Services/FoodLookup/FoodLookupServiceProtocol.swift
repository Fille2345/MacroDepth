// Services/FoodLookup/FoodLookupServiceProtocol.swift

import Foundation

/// Finds foods by barcode or name. A real database such as Open Food Facts plugs in
/// here, without changing the view models or views.
protocol FoodLookupServiceProtocol: Sendable {
    /// The product with this barcode, or `nil` if the database doesn't have it.
    func product(forBarcode barcode: String) async throws -> FoodProduct?

    /// Foods matching `query`, best match first.
    func searchFoods(matching query: String) async throws -> [FoodProduct]
}
