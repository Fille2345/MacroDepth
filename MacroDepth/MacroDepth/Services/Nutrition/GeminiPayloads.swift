// Services/Nutrition/GeminiPayloads.swift

import Foundation

// The JSON shapes Gemini is asked to produce via `response_schema`.
// These are the decoded *payload* text inside the response candidate; the HTTP
// envelope is handled by `GeminiGenerateContentResponse`.
// Mapping to domain types validates everything the model returns.

/// The `generateContent` request body: system prompt, text prompt and base64 images.
/// Each image follows a text label, so the model knows which view it's looking at.
struct GeminiGenerateContentRequest: Encodable, Sendable {
    enum Part: Encodable, Sendable, Equatable {
        case text(String)
        case jpeg(Data)

        private enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        private enum InlineDataKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .jpeg(let data):
                var inlineData = container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                try inlineData.encode("image/jpeg", forKey: .mimeType)
                try inlineData.encode(data.base64EncodedString(), forKey: .data)
            }
        }
    }

    struct SystemInstruction: Encodable, Sendable {
        let parts: [Part]
    }

    struct Content: Encodable, Sendable {
        let role: String
        let parts: [Part]
    }

    struct GenerationConfig: Encodable, Sendable {
        let responseMimeType = "application/json"
        let responseSchema: GeminiResponseSchema

        enum CodingKeys: String, CodingKey {
            case responseMimeType = "response_mime_type"
            case responseSchema = "response_schema"
        }
    }

    let systemInstruction: SystemInstruction
    let contents: [Content]
    let generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig = "generation_config"
    }

    /// Stage 1 request.
    static func detection(images: [Data], userNotes: String?) throws -> GeminiGenerateContentRequest {
        try make(prompt: GeminiPrompts.detectionPrompt(userNotes: userNotes), images: images, schema: .detection)
    }

    /// Stage 2 request. The text prompt carries each item's measured LiDAR volume.
    static func nutrition(queries: [NutritionQuery], images: [Data], userNotes: String?) throws -> GeminiGenerateContentRequest {
        try make(
            prompt: GeminiPrompts.nutritionPrompt(queries: queries, userNotes: userNotes),
            images: images,
            schema: .nutrition(queryIDs: queries.map(\.id))
        )
    }

    private static func make(prompt: String, images: [Data], schema: GeminiResponseSchema) throws -> GeminiGenerateContentRequest {
        try NutritionImageUpload.validate(images)
        var parts: [Part] = [.text(prompt)]
        for (index, image) in images.enumerated() {
            parts.append(.text(GeminiPrompts.imageLabel(at: index)))
            parts.append(.jpeg(image))
        }
        return GeminiGenerateContentRequest(
            systemInstruction: SystemInstruction(parts: [.text(GeminiPrompts.systemInstruction)]),
            contents: [Content(role: "user", parts: parts)],
            generationConfig: GenerationConfig(responseSchema: schema)
        )
    }
}

/// Stage 1 payload:
/// `{"items":[{"label":"…","category":"meat","box_2d":[ymin,xmin,ymax,xmax],"confidence":0.9}]}`
struct GeminiDetectionPayload: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let label: String
        let category: String
        let box2D: [Double]
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case label
            case category
            case box2D = "box_2d"
            case confidence
        }
    }

    let items: [Item]

    /// Valid items mapped to the domain. Entries with an empty label or an
    /// invalid box are dropped; unknown categories become `.other`.
    func detectedItems() -> [DetectedFoodItem] {
        items.compactMap { item in
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, let box = NormalizedBoundingBox(geminiBox2D: item.box2D) else { return nil }
            return DetectedFoodItem(
                label: label,
                category: FoodCategory(rawValue: item.category) ?? .other,
                boundingBox: box,
                confidence: item.confidence ?? 0.5
            )
        }
    }
}

/// Stage 2 payload. `id` echoes the query's UUID so results can be matched.
struct GeminiNutritionPayload: Decodable, Sendable {
    struct Per100Grams: Decodable, Sendable {
        let proteinGrams: Double
        let carbohydrateGrams: Double
        let fatGrams: Double
        let fiberGrams: Double?
        let energyKilocalories: Double?

        enum CodingKeys: String, CodingKey {
            case proteinGrams = "protein_g"
            case carbohydrateGrams = "carbohydrate_g"
            case fatGrams = "fat_g"
            case fiberGrams = "fiber_g"
            case energyKilocalories = "energy_kcal"
        }
    }

    struct Item: Decodable, Sendable {
        let id: String
        let label: String?
        let densityGramsPerCubicCentimeter: Double?
        let estimatedGrams: Double?
        let per100Grams: Per100Grams
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case label
            case densityGramsPerCubicCentimeter = "density_g_per_cm3"
            case estimatedGrams = "estimated_grams"
            case per100Grams = "per_100g"
            case confidence
        }
    }

    /// Small tolerance for rounding in the model's per-100 g values.
    static let maximumMacroMassPer100Grams = 102.0

    let items: [Item]

    /// Validated estimates for the given queries. Unknown or duplicate ids,
    /// invalid macros and physically impossible per-100 g totals are dropped.
    /// Stated energy that disagrees with the macros is replaced by the Atwater value.
    func estimates(matching queries: [NutritionQuery]) -> [NutritionEstimate] {
        let queriesByID = Dictionary(queries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()

        return items.compactMap { item -> NutritionEstimate? in
            guard let id = UUID(uuidString: item.id.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let query = queriesByID[id],
                  seen.insert(id).inserted else { return nil }

            let macros = MacroNutrients(
                proteinGrams: item.per100Grams.proteinGrams,
                carbohydrateGrams: item.per100Grams.carbohydrateGrams,
                fatGrams: item.per100Grams.fatGrams,
                fiberGrams: item.per100Grams.fiberGrams ?? 0,
                energyKilocalories: item.per100Grams.energyKilocalories
            ).reconcilingEnergy()

            guard macros.isValid, macros.macronutrientMassGrams <= Self.maximumMacroMassPer100Grams else { return nil }

            return NutritionEstimate(
                id: id,
                label: query.label,
                category: query.category,
                macrosPer100Grams: macros,
                suggestedDensity: Self.positiveFinite(item.densityGramsPerCubicCentimeter),
                visualEstimateGrams: Self.positiveFinite(item.estimatedGrams),
                confidence: item.confidence ?? 0.5
            )
        }
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
