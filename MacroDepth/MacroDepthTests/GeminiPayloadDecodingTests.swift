// MacroDepthTests/GeminiPayloadDecodingTests.swift

import Foundation
import Testing
@testable import MacroDepth

struct GeminiPayloadDecodingTests {
    @Test func decodesDetectionPayloadAndDropsInvalidItems() throws {
        let json = """
        {
          "items": [
            {"label": "Grilled chicken breast", "category": "meat", "box_2d": [313, 508, 547, 762], "confidence": 0.88},
            {"label": "Mystery garnish", "category": "space_food", "box_2d": [10, 10, 120, 140]},
            {"label": "Broken box", "category": "vegetable", "box_2d": [500, 500, 100, 100], "confidence": 0.9},
            {"label": "   ", "category": "fruit", "box_2d": [0, 0, 500, 500], "confidence": 0.9}
          ]
        }
        """
        let payload = try JSONDecoder().decode(GeminiDetectionPayload.self, from: Data(json.utf8))
        let items = payload.detectedItems()

        #expect(items.count == 2)
        #expect(items[0].label == "Grilled chicken breast")
        #expect(items[0].category == .meat)
        #expect(abs(items[0].boundingBox.minX - 0.508) < 1e-9)
        #expect(items[1].category == .other)
        #expect(items[1].confidence == 0.5)
    }

    @Test func decodesNutritionPayloadAndValidates() throws {
        let rice = NutritionQuery(id: UUID(), label: "Steamed white rice", category: .grainOrStarch, measuredVolume: nil)
        let chicken = NutritionQuery(id: UUID(), label: "Grilled chicken breast", category: .meat, measuredVolume: nil)
        let broken = NutritionQuery(id: UUID(), label: "Impossible food", category: .other, measuredVolume: nil)

        let json = """
        {
          "items": [
            {
              "id": "\(rice.id.uuidString.lowercased())",
              "label": "rice",
              "density_g_per_cm3": 0.85,
              "estimated_grams": 180,
              "per_100g": {"protein_g": 2.7, "carbohydrate_g": 28, "fat_g": 0.3, "fiber_g": 0.4, "energy_kcal": 130},
              "confidence": 0.9
            },
            {
              "id": "\(chicken.id.uuidString)",
              "density_g_per_cm3": -2,
              "per_100g": {"protein_g": 31, "carbohydrate_g": 0, "fat_g": 3.6, "energy_kcal": 900}
            },
            {
              "id": "\(chicken.id.uuidString)",
              "per_100g": {"protein_g": 1, "carbohydrate_g": 1, "fat_g": 1}
            },
            {
              "id": "\(broken.id.uuidString)",
              "per_100g": {"protein_g": 60, "carbohydrate_g": 60, "fat_g": 10}
            },
            {
              "id": "\(UUID().uuidString)",
              "per_100g": {"protein_g": 1, "carbohydrate_g": 1, "fat_g": 1}
            }
          ]
        }
        """
        let payload = try JSONDecoder().decode(GeminiNutritionPayload.self, from: Data(json.utf8))
        let estimates = payload.estimates(matching: [rice, chicken, broken])

        #expect(estimates.count == 2)

        let riceEstimate = try #require(estimates.first { $0.id == rice.id })
        #expect(riceEstimate.label == "Steamed white rice")   // query label wins
        #expect(riceEstimate.suggestedDensity == 0.85)
        #expect(riceEstimate.visualEstimateGrams == 180)
        #expect(riceEstimate.macrosPer100Grams.energyKilocalories == 130)

        let chickenEstimate = try #require(estimates.first { $0.id == chicken.id })
        #expect(chickenEstimate.suggestedDensity == nil)                 // negative density discarded
        #expect(chickenEstimate.macrosPer100Grams.proteinGrams == 31)    // first duplicate kept
        #expect(abs(chickenEstimate.macrosPer100Grams.energyKilocalories - 156.4) < 1e-9) // 900 kcal reconciled
        #expect(chickenEstimate.confidence == 0.5)
    }

    @Test func rejectsMalformedPayload() {
        let json = #"{"items": [{"label": "x", "category": "meat"}]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GeminiDetectionPayload.self, from: Data(json.utf8))
        }
    }
}
