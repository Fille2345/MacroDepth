// Services/Nutrition/GeminiNutritionService.swift

import Foundation

/// Live two-stage analysis. Builds the requests, then validates what the model
/// returns through the `GeminiPayloads` types.
struct GeminiNutritionService: NutritionServiceProtocol {
    private let client: any GeminiAPIClient

    init(client: any GeminiAPIClient) {
        self.client = client
    }

    init(configuration: AppConfiguration) {
        self.init(client: URLSessionGeminiAPIClient(configuration: configuration))
    }

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        let request = try GeminiGenerateContentRequest.detection(images: images, userNotes: userNotes)
        let text = try await client.generateContent(request)
        return try Self.decode(GeminiDetectionPayload.self, from: text).detectedItems()
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        guard !queries.isEmpty else { return [] }
        let request = try GeminiGenerateContentRequest.nutrition(queries: queries, images: images, userNotes: userNotes)
        let text = try await client.generateContent(request)
        return try Self.decode(GeminiNutritionPayload.self, from: text).estimates(matching: queries)
    }

    private static func decode<Payload: Decodable>(_ type: Payload.Type, from text: String) throws -> Payload {
        do {
            return try JSONDecoder().decode(type, from: Data(text.utf8))
        } catch {
            throw NutritionServiceError.decodingFailed("the result didn't match the expected format")
        }
    }
}
