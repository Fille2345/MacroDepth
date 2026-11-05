// Domain/Measurement/PortionCalculator.swift

import Foundation

/// The mass of one food item and how it was obtained.
struct PortionEstimate: Sendable, Hashable {
    enum Source: String, Sendable, Codable {
        /// grams = measured volume × validated density.
        case lidarVolume
        /// Gemini estimated grams from the photo alone (no depth available).
        case visualEstimate
        /// The user edited the weight; treated as ground truth.
        case userAdjusted
        /// Copied from a saved meal template rather than measured for this meal.
        case savedMeal
        /// A weight the user chose for a food they found by barcode or search.
        case manualEntry

        var displayName: String {
            switch self {
            case .lidarVolume: "LiDAR"
            case .visualEstimate: "Photo estimate"
            case .userAdjusted: "Adjusted"
            case .savedMeal: "Saved meal"
            case .manualEntry: "Manual"
            }
        }
    }

    let grams: Double
    let source: Source
    /// Combined confidence in [0, 1].
    let confidence: Double
    let volume: VolumeMeasurement?
    let densityGramsPerCubicCentimeter: Double?
    /// True when the suggested density was missing or out of bounds and had to be replaced or clamped.
    let densityWasAdjusted: Bool
}

/// Deterministic volume → mass logic. Gemini only *suggests* a density; this type
/// validates it against category bounds and does the arithmetic on device so the
/// result is reproducible and testable.
enum PortionCalculator {
    static let maximumPlausibleItemGrams = 3_000.0
    static let minimumPlausibleItemGrams = 1.0
    /// Photo-only estimates are much less reliable than measured volume.
    static let visualEstimateConfidenceFactor = 0.6
    static let adjustedDensityConfidenceFactor = 0.8
    /// Caps how much volume uncertainty can reduce confidence.
    static let maximumUncertaintyPenalty = 0.9

    /// LiDAR path: `grams = V × ρ`, where ρ is the suggested density clamped to the
    /// category's plausible range (or the category's typical density when missing).
    ///
    /// Confidence = model confidence × (1 − relative volume uncertainty, floored at 0.1)
    ///              × 0.8 if the density had to be adjusted.
    static func portion(
        volume: VolumeMeasurement,
        suggestedDensity: Double?,
        category: FoodCategory,
        modelConfidence: Double
    ) -> PortionEstimate {
        let range = category.plausibleDensityRange
        let density: Double
        let adjusted: Bool
        if let suggestedDensity, suggestedDensity.isFinite, suggestedDensity > 0 {
            density = min(max(suggestedDensity, range.lowerBound), range.upperBound)
            adjusted = density != suggestedDensity
        } else {
            density = category.typicalDensity
            adjusted = true
        }

        let grams = min(volume.cubicCentimeters * density, maximumPlausibleItemGrams)
        let uncertaintyFactor = 1 - min(volume.relativeUncertainty, maximumUncertaintyPenalty)
        var confidence = modelConfidence.clampedToUnitInterval * uncertaintyFactor
        if adjusted {
            confidence *= adjustedDensityConfidenceFactor
        }

        return PortionEstimate(
            grams: grams,
            source: .lidarVolume,
            confidence: confidence.clampedToUnitInterval,
            volume: volume,
            densityGramsPerCubicCentimeter: density,
            densityWasAdjusted: adjusted
        )
    }

    /// Fallback path when no depth is available. Returns `nil` for unusable estimates.
    static func portion(visualEstimateGrams grams: Double, modelConfidence: Double) -> PortionEstimate? {
        guard grams.isFinite, grams >= minimumPlausibleItemGrams else { return nil }
        return PortionEstimate(
            grams: min(grams, maximumPlausibleItemGrams),
            source: .visualEstimate,
            confidence: (modelConfidence.clampedToUnitInterval * visualEstimateConfidenceFactor).clampedToUnitInterval,
            volume: nil,
            densityGramsPerCubicCentimeter: nil,
            densityWasAdjusted: false
        )
    }

    /// Weights a person can enter directly.
    static let manualEntryRange = minimumPlausibleItemGrams...maximumPlausibleItemGrams

    /// A weight typed for a food found by barcode or search. `nil` if it's out of range.
    static func portion(manualGrams grams: Double) -> PortionEstimate? {
        guard grams.isFinite, manualEntryRange.contains(grams) else { return nil }
        return PortionEstimate(
            grams: grams,
            source: .manualEntry,
            confidence: 1,
            volume: nil,
            densityGramsPerCubicCentimeter: nil,
            densityWasAdjusted: false
        )
    }

    /// Applies a manual weight correction. Measurement metadata is kept for reference.
    static func adjusted(_ portion: PortionEstimate, toGrams grams: Double) -> PortionEstimate {
        let validGrams = grams.isFinite ? min(max(grams, 0), maximumPlausibleItemGrams) : portion.grams
        return PortionEstimate(
            grams: validGrams,
            source: .userAdjusted,
            confidence: 1,
            volume: portion.volume,
            densityGramsPerCubicCentimeter: portion.densityGramsPerCubicCentimeter,
            densityWasAdjusted: portion.densityWasAdjusted
        )
    }
}
