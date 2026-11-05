// Domain/Food/FoodProduct.swift

import Foundation

/// A food from a barcode or search lookup, with the values needed to log any portion of it.
struct FoodProduct: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    var brand: String? = nil
    let category: FoodCategory
    let macrosPer100Grams: MacroNutrients
    /// The weight to suggest first. The user can change it.
    let typicalServingGrams: Double
    var barcode: String? = nil
}

/// Retail food barcodes: EAN-8, UPC-A and EAN-13.
enum FoodBarcode {
    /// The digits if `text` is a valid barcode (with a correct check digit), otherwise `nil`.
    static func normalized(_ text: String) -> String? {
        let digits = text.filter { !$0.isWhitespace && $0 != "-" }
        guard [8, 12, 13].contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        let values = digits.compactMap(\.wholeNumberValue)
        // Counting from the right, the check digit has weight 1, then weights alternate 3 and 1.
        let sum = values.reversed().enumerated().reduce(0) { total, entry in
            total + entry.element * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return sum.isMultiple(of: 10) ? digits : nil
    }
}
