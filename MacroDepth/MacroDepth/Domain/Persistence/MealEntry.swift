// Domain/Persistence/MealEntry.swift

import Foundation
import SwiftData

/// A logged meal. Daily summaries are derived by querying meals in a day's
/// date interval rather than stored, so totals can never drift out of sync.
///
/// Enums are stored as raw strings: SwiftData on iOS 17 handles them more
/// reliably in predicates and migrations than enum-typed attributes.
@Model
final class MealEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var mealTypeRawValue: String
    /// File name (not path) inside the capture image directory.
    var imageFileName: String?
    /// The user's notes or pasted recipe. Optional, so existing stores migrate automatically.
    var notes: String?
    /// The template this meal was logged from, if any. It's `nil` for scanned meals and
    /// once the template is deleted. Optional, so existing stores migrate automatically.
    var savedMeal: SavedMeal?

    @Relationship(deleteRule: .cascade, inverse: \LoggedFoodItem.meal)
    var items: [LoggedFoodItem] = []

    init(id: UUID = UUID(), timestamp: Date, mealType: MealType, imageFileName: String? = nil, notes: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.mealTypeRawValue = mealType.rawValue
        self.imageFileName = imageFileName
        self.notes = notes
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRawValue) ?? .snack }
        set { mealTypeRawValue = newValue.rawValue }
    }

    /// Items in the order they were captured (SwiftData relationships are unordered).
    var orderedItems: [LoggedFoodItem] {
        items.sorted { $0.sortIndex < $1.sortIndex }
    }

    var totalMacros: MacroNutrients {
        items.map(\.totalMacros).sum()
    }
}
