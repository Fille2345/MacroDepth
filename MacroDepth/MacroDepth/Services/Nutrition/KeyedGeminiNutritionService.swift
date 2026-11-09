// Services/Nutrition/KeyedGeminiNutritionService.swift

import Foundation

/// Gemini analysis using the key the user saved in Settings. The key is read
/// for every request, so adding, replacing or removing it takes effect at once.
struct KeyedGeminiNutritionService: NutritionServiceProtocol {
    typealias ClientFactory = @Sendable (AppConfiguration) -> any GeminiAPIClient

    private let store: any APIKeyStoring
    private let modelID: String
    private let makeClient: ClientFactory

    init(
        store: any APIKeyStoring,
        modelID: String,
        makeClient: @escaping ClientFactory = { URLSessionGeminiAPIClient(configuration: $0) }
    ) {
        self.store = store
        self.modelID = modelID
        self.makeClient = makeClient
    }

    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem] {
        try await service().detectFoodItems(in: images, userNotes: userNotes)
    }

    func estimateNutrition(for queries: [NutritionQuery], images: [Data], userNotes: String?) async throws -> [NutritionEstimate] {
        try await service().estimateNutrition(for: queries, images: images, userNotes: userNotes)
    }

    private func service() throws -> GeminiNutritionService {
        let key: String?
        do {
            key = try store.load()
        } catch {
            throw NutritionServiceError.invalidConfiguration("the saved API key couldn't be read.")
        }
        guard let key, !key.isEmpty else { throw NutritionServiceError.missingAPIKey }
        return GeminiNutritionService(client: makeClient(AppConfiguration(apiKey: key, modelID: modelID)))
    }
}
