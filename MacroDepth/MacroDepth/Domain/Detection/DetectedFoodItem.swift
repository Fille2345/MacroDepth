// Domain/Detection/DetectedFoodItem.swift

import Foundation

/// One food item found in a captured photo (stage 1 of the analysis pipeline).
/// The `id` is carried through volume measurement, nutrition estimation and the
/// final draft so results can be matched without relying on labels or order.
struct DetectedFoodItem: Sendable, Hashable, Identifiable {
    let id: UUID
    var label: String
    var category: FoodCategory
    var boundingBox: NormalizedBoundingBox
    /// Model confidence in [0, 1].
    var confidence: Double

    init(
        id: UUID = UUID(),
        label: String,
        category: FoodCategory,
        boundingBox: NormalizedBoundingBox,
        confidence: Double
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.boundingBox = boundingBox
        self.confidence = confidence.clampedToUnitInterval
    }
}
