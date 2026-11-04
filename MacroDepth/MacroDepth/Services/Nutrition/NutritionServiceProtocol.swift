// Services/Nutrition/NutritionServiceProtocol.swift

import Foundation

/// Two-stage food analysis.
///
/// `images` holds one or two JPEGs of the same plate, top-down first. Bounding
/// boxes always refer to the first image, because that's the frame depth belongs to.
/// `userNotes` is optional meal context that refines identification and nutrition.
///
/// 1. `detectFoodItems` — find items and their bounding boxes in the photo.
/// 2. (on device) measure each item's volume from depth inside its box.
/// 3. `estimateNutrition` — per-100 g macros and a density suggestion per item,
///    or a photo-only gram estimate when no volume was measured.
///
/// The live implementation (`GeminiNutritionService`) sits behind this protocol
/// and talks to the network through a swappable `GeminiAPIClient`, so a backend
/// proxy can replace the direct Gemini call without touching callers.
protocol NutritionServiceProtocol: Sendable {
    func detectFoodItems(in images: [Data], userNotes: String?) async throws -> [DetectedFoodItem]

    func estimateNutrition(
        for queries: [NutritionQuery],
        images: [Data],
        userNotes: String?
    ) async throws -> [NutritionEstimate]
}

/// The image rules every `NutritionServiceProtocol` implementation enforces.
enum NutritionImageUpload {
    static let maximumCount = 2

    static func validate(_ images: [Data]) throws {
        guard !images.isEmpty, !images.contains(where: \.isEmpty) else {
            throw NutritionServiceError.invalidRequest("The captured image is empty.")
        }
        guard images.count <= maximumCount else {
            throw NutritionServiceError.invalidRequest("A scan can include at most \(maximumCount) photos.")
        }
    }
}
