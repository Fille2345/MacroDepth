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
}
