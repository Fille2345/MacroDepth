// Domain/Drafts/MealDraft.swift

import Foundation

/// An editable, not-yet-saved food item shown on the review screen.
struct FoodItemDraft: Sendable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var category: FoodCategory
    var portion: PortionEstimate
    var macrosPer100Grams: MacroNutrients
    var boundingBox: NormalizedBoundingBox?
    /// The dimensions behind a depth-measured portion. `nil` for photo estimates.
    var measuredSize: FoodVolumeEstimate? = nil

    var totalMacros: MacroNutrients {
        macrosPer100Grams.forPortion(grams: portion.grams)
    }
}

/// A meal ready to be persisted.
struct MealDraft: Sendable, Hashable {
    var timestamp: Date
    var mealType: MealType
    var items: [FoodItemDraft]
    var imageJPEGData: Data?
    var userNotes: String? = nil

    var totalMacros: MacroNutrients {
        items.map(\.totalMacros).sum()
    }
}

/// Joins detections, nutrition estimates and (optional) measured volumes into drafts.
enum MealDraftBuilder {
    /// Items without a matching estimate, or without either a volume or a usable
    /// visual estimate, are dropped.
    static func makeItems(
        detections: [DetectedFoodItem],
        estimates: [NutritionEstimate],
        volumes: [UUID: VolumeMeasurement],
        measuredSizes: [UUID: FoodVolumeEstimate] = [:]
    ) -> [FoodItemDraft] {
        let estimatesByID = Dictionary(estimates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return detections.compactMap { detection -> FoodItemDraft? in
            guard let estimate = estimatesByID[detection.id] else { return nil }
            // Both stages must be confident for the result to be.
            let combinedConfidence = min(detection.confidence, estimate.confidence)

            let portion: PortionEstimate?
            if let volume = volumes[detection.id] {
                portion = PortionCalculator.portion(
                    volume: volume,
                    suggestedDensity: estimate.suggestedDensity,
                    category: estimate.category,
                    modelConfidence: combinedConfidence
                )
            } else if let grams = estimate.visualEstimateGrams {
                portion = PortionCalculator.portion(visualEstimateGrams: grams, modelConfidence: combinedConfidence)
            } else {
                portion = nil
            }

            guard let portion else { return nil }
            return FoodItemDraft(
                id: detection.id,
                name: estimate.label,
                category: estimate.category,
                portion: portion,
                macrosPer100Grams: estimate.macrosPer100Grams,
                boundingBox: detection.boundingBox,
                measuredSize: measuredSizes[detection.id]
            )
        }
    }
}
