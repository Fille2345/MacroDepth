// Services/Nutrition/GeminiResponseSchema.swift

import Foundation

/// The `response_schema` sent with each request, in Gemini's OpenAPI-style format.
/// It constrains the JSON's shape; `GeminiPayloads` still validates the values.
/// Field names must match the `Decodable` payloads in `GeminiPayloads.swift`.
indirect enum GeminiResponseSchema: Encodable, Sendable {
    case string(allowedValues: [String]? = nil)
    case number
    case array(items: GeminiResponseSchema, exactCount: Int? = nil)
    case object([Property])

    struct Property: Sendable {
        let name: String
        let schema: GeminiResponseSchema
        var isRequired = true
    }

    /// Stage 1: matches `GeminiDetectionPayload`.
    static let detection = GeminiResponseSchema.object([
        Property(name: "items", schema: .array(items: .object([
            Property(name: "label", schema: .string()),
            Property(name: "category", schema: .string(allowedValues: FoodCategory.allCases.map(\.rawValue))),
            Property(name: "box_2d", schema: .array(items: .number, exactCount: 4)),
            Property(name: "confidence", schema: .number),
        ]))),
    ])

    /// Stage 2: matches `GeminiNutritionPayload`. Limiting `id` to the queries' ids
    /// stops a mistyped UUID from losing an item's result.
    static func nutrition(queryIDs: [UUID]) -> GeminiResponseSchema {
        .object([
            Property(name: "items", schema: .array(items: .object([
                Property(name: "id", schema: .string(allowedValues: queryIDs.map(\.uuidString))),
                Property(name: "label", schema: .string(), isRequired: false),
                Property(name: "density_g_per_cm3", schema: .number),
                Property(name: "estimated_grams", schema: .number, isRequired: false),
                Property(name: "per_100g", schema: .object([
                    Property(name: "protein_g", schema: .number),
                    Property(name: "carbohydrate_g", schema: .number),
                    Property(name: "fat_g", schema: .number),
                    Property(name: "fiber_g", schema: .number),
                    Property(name: "energy_kcal", schema: .number),
                ])),
                Property(name: "confidence", schema: .number),
            ]))),
        ])
    }

    // MARK: Encoding

    private enum CodingKeys: String, CodingKey {
        case type, format, `enum`, items, minItems, maxItems, properties, required, propertyOrdering
    }

    private struct PropertyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let allowedValues):
            try container.encode("STRING", forKey: .type)
            if let allowedValues {
                try container.encode("enum", forKey: .format)
                try container.encode(allowedValues, forKey: .enum)
            }
        case .number:
            try container.encode("NUMBER", forKey: .type)
        case .array(let items, let exactCount):
            try container.encode("ARRAY", forKey: .type)
            try container.encode(items, forKey: .items)
            if let exactCount {
                try container.encode(exactCount, forKey: .minItems)
                try container.encode(exactCount, forKey: .maxItems)
            }
        case .object(let properties):
            try container.encode("OBJECT", forKey: .type)
            var encodedProperties = container.nestedContainer(keyedBy: PropertyKey.self, forKey: .properties)
            for property in properties {
                try encodedProperties.encode(property.schema, forKey: PropertyKey(stringValue: property.name))
            }
            try container.encode(properties.filter(\.isRequired).map(\.name), forKey: .required)
            try container.encode(properties.map(\.name), forKey: .propertyOrdering)
        }
    }
}
