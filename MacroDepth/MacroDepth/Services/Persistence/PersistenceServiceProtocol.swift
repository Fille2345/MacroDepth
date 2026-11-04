// Services/Persistence/PersistenceServiceProtocol.swift

import Foundation

/// Storage boundary for logged meals.
///
/// Main-actor isolated because SwiftData models are bound to the context that
/// fetched them. View models receive `@Model` objects and must only use them on
/// the main actor. Input crosses the boundary as `Sendable` drafts.
@MainActor
protocol PersistenceServiceProtocol: AnyObject {
    func meals(in interval: DateInterval) throws -> [MealEntry]
    func meals(on day: Date) throws -> [MealEntry]

    @discardableResult
    func saveMeal(_ draft: MealDraft) async throws -> MealEntry

    func deleteMeal(_ meal: MealEntry) async throws

    func imageURL(for meal: MealEntry) -> URL?

    /// The stored profile as a value, or `nil` before setup.
    func currentProfile() throws -> UserProfileDraft?

    /// Creates or replaces the single stored profile.
    func saveProfile(_ draft: UserProfileDraft) throws

    /// Yields after every saved change to meals or the profile, wherever it was made.
    /// Each call returns an independent stream that ends when its consumer is cancelled.
    func changes() -> AsyncStream<Void>
}
