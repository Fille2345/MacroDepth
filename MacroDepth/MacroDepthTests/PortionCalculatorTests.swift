// MacroDepthTests/PortionCalculatorTests.swift

import Foundation
import Testing
@testable import MacroDepth

struct PortionCalculatorTests {
    private func volume(_ cubicCentimeters: Double, uncertainty: Double = 0) throws -> VolumeMeasurement {
        try #require(VolumeMeasurement(
            cubicCentimeters: cubicCentimeters,
            uncertaintyCubicCentimeters: uncertainty,
            sampleCount: 500,
            method: .singleFrameHeightField
        ))
    }

    @Test func usesSuggestedDensityWithinBounds() throws {
        let portion = PortionCalculator.portion(
            volume: try volume(200),
            suggestedDensity: 1.05,
            category: .meat,
            modelConfidence: 0.9
        )
        #expect(abs(portion.grams - 210) < 1e-9)
        #expect(portion.source == .lidarVolume)
        #expect(!portion.densityWasAdjusted)
        #expect(abs(portion.confidence - 0.9) < 1e-9)
    }

    @Test func clampsImplausibleDensity() throws {
        // Leafy greens can't be 1.4 g/cm³ in bulk; clamp to the category maximum.
        let portion = PortionCalculator.portion(
            volume: try volume(300),
            suggestedDensity: 1.4,
            category: .leafyVegetable,
            modelConfidence: 1
        )
        let upper = FoodCategory.leafyVegetable.plausibleDensityRange.upperBound
        #expect(portion.densityGramsPerCubicCentimeter == upper)
        #expect(abs(portion.grams - 300 * upper) < 1e-9)
        #expect(portion.densityWasAdjusted)
        #expect(portion.confidence == PortionCalculator.adjustedDensityConfidenceFactor)
    }

    @Test(arguments: [nil, 0, -1, Double.nan, Double.infinity] as [Double?])
    func fallsBackToTypicalDensity(suggested: Double?) throws {
        let portion = PortionCalculator.portion(
            volume: try volume(100),
            suggestedDensity: suggested,
            category: .grainOrStarch,
            modelConfidence: 1
        )
        #expect(portion.densityGramsPerCubicCentimeter == FoodCategory.grainOrStarch.typicalDensity)
        #expect(portion.densityWasAdjusted)
    }

    @Test func volumeUncertaintyReducesConfidence() throws {
        let precise = PortionCalculator.portion(volume: try volume(100, uncertainty: 10), suggestedDensity: 1, category: .meat, modelConfidence: 1)
        let noisy = PortionCalculator.portion(volume: try volume(100, uncertainty: 60), suggestedDensity: 1, category: .meat, modelConfidence: 1)
        #expect(precise.confidence > noisy.confidence)
        #expect(abs(noisy.confidence - 0.4) < 1e-9)
    }

    @Test func capsImplausiblyLargePortions() throws {
        let portion = PortionCalculator.portion(volume: try volume(10_000), suggestedDensity: 1, category: .soupOrLiquid, modelConfidence: 1)
        #expect(portion.grams == PortionCalculator.maximumPlausibleItemGrams)
    }

    @Test func visualEstimatePathPenalizesConfidence() throws {
        let portion = try #require(PortionCalculator.portion(visualEstimateGrams: 150, modelConfidence: 0.9))
        #expect(portion.grams == 150)
        #expect(portion.source == .visualEstimate)
        #expect(abs(portion.confidence - 0.9 * PortionCalculator.visualEstimateConfidenceFactor) < 1e-9)
        #expect(PortionCalculator.portion(visualEstimateGrams: 0.2, modelConfidence: 1) == nil)
        #expect(PortionCalculator.portion(visualEstimateGrams: .nan, modelConfidence: 1) == nil)
    }

    @Test func userAdjustmentKeepsMeasurementMetadata() throws {
        let measured = PortionCalculator.portion(volume: try volume(100), suggestedDensity: 1, category: .meat, modelConfidence: 0.7)
        let adjusted = PortionCalculator.adjusted(measured, toGrams: 125)
        #expect(adjusted.grams == 125)
        #expect(adjusted.source == .userAdjusted)
        #expect(adjusted.confidence == 1)
        #expect(adjusted.volume == measured.volume)
    }

    @Test func draftBuilderPrefersMeasuredVolume() throws {
        let detections = SampleScene.sampleDetections()
        let chicken = try #require(detections.first { $0.category == .meat })
        let estimates = detections.map { detection in
            NutritionEstimate(
                id: detection.id,
                label: detection.label,
                category: detection.category,
                macrosPer100Grams: MacroNutrients(proteinGrams: 10, carbohydrateGrams: 10, fatGrams: 1),
                suggestedDensity: 1.0,
                visualEstimateGrams: 100,
                confidence: 0.9
            )
        }
        let drafts = MealDraftBuilder.makeItems(
            detections: detections,
            estimates: estimates,
            volumes: [chicken.id: try volume(150)]
        )
        #expect(drafts.count == detections.count)
        let chickenDraft = try #require(drafts.first { $0.id == chicken.id })
        #expect(chickenDraft.portion.source == .lidarVolume)
        #expect(abs(chickenDraft.portion.grams - 150) < 1e-9)
        #expect(drafts.filter { $0.portion.source == .visualEstimate }.count == detections.count - 1)
    }

    @Test func draftBuilderDropsUnmatchedItems() {
        let detections = SampleScene.sampleDetections()
        let drafts = MealDraftBuilder.makeItems(detections: detections, estimates: [], volumes: [:])
        #expect(drafts.isEmpty)
    }
}
