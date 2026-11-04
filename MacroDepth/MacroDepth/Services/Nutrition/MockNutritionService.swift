// Services/Nutrition/MockNutritionService.swift

import Foundation

/// Deterministic stand-in for Gemini, built on the sample scene's reference data.
/// It validates images like the live service, but notes don't change its results.
struct MockNutritionService: NutritionServiceProtocol {
    enum Behavior: Sendable, Equatable {
        case success
        case noFoodDetected
        case failure(NutritionServiceError)
    }

    /// Per-100 g values used for labels the sample scene doesn't know.
    static let genericMacrosPer100Grams = MacroNutrients(
        proteinGrams: 5,
        carbohydrateGrams: 15,
        fatGrams: 5,
        fiberGrams: 1
    )
    static let genericVisualEstimateGrams = 120.0

    let behavior: Behavior
    let latency: Duration

    init(behavior: Behavior = .success, latency: Duration = .milliseconds(600)) {
        self.behavior = behavior
        self.latency = latency
    }

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        try NutritionImageUpload.validate(images)
        try await Task.sleep(for: latency)
        switch behavior {
        case .success: return SampleScene.sampleDetections()
        case .noFoodDetected: return []
        case .failure(let error): throw error
        }
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        guard !queries.isEmpty else { return [] }
        try NutritionImageUpload.validate(images)
        try await Task.sleep(for: latency)
        if case .failure(let error) = behavior { throw error }

        return queries.map { query in
            let reference = SampleScene.referenceFood(matching: query.label)
            return NutritionEstimate(
                id: query.id,
                label: query.label,
                category: query.category,
                macrosPer100Grams: reference?.macrosPer100Grams ?? Self.genericMacrosPer100Grams,
                suggestedDensity: reference?.densityGramsPerCubicCentimeter ?? query.category.typicalDensity,
                // Like the real prompt: grams are only estimated when no volume was measured.
                visualEstimateGrams: query.measuredVolume == nil
                    ? (reference?.visualEstimateGrams ?? Self.genericVisualEstimateGrams)
                    : nil,
                confidence: reference == nil ? 0.4 : 0.85
            )
        }
    }
}
