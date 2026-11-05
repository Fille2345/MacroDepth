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
    /// A typical whole food from `GenericFoodCatalog`, not a specific packaged product.
    var isGeneric = false
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

    /// The 12-digit UPC-A form of an 8-digit UPC-E code, which databases list products
    /// under. UPC-E drops zeros from UPC-A, and its check digit is the UPC-A one, so it
    /// can't be checked until it's expanded. `nil` if it isn't valid UPC-E.
    static func upcA(fromUPCE code: String) -> String? {
        let digits = Array(code)
        guard digits.count == 8, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else { return nil }
        let system = digits[0]
        let body = Array(digits[1...6])
        let check = digits[7]

        let middle: [Character]
        switch body[5] {
        case "0", "1", "2":
            middle = [body[0], body[1], body[5], "0", "0", "0", "0", body[2], body[3], body[4]]
        case "3":
            middle = [body[0], body[1], body[2], "0", "0", "0", "0", "0", body[3], body[4]]
        case "4":
            middle = [body[0], body[1], body[2], body[3], "0", "0", "0", "0", "0", body[4]]
        default:
            middle = [body[0], body[1], body[2], body[3], body[4], "0", "0", "0", "0", body[5]]
        }
        return normalized(String([system] + middle + [check]))
    }
}
