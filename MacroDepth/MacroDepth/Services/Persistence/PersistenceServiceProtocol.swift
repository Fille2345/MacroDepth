// Services/Persistence/PersistenceServiceProtocol.swift

import Foundation

/// Storage boundary for logged meals, the profile, body weight and saved meals.
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

    // MARK: Body weight

    /// Entries in the interval, oldest first.
    func weightEntries(in interval: DateInterval) throws -> [WeightEntry]

    func latestWeightEntry() throws -> WeightEntry?

    /// Records the day's weight, replacing any earlier entry for that calendar day.
    @discardableResult
    func saveWeight(kilograms: Double, on date: Date) throws -> WeightEntry

    func deleteWeightEntry(_ entry: WeightEntry) throws

    // MARK: Saved meals

    /// All templates, most recently changed first.
    func savedMeals() throws -> [SavedMeal]

    @discardableResult
    func saveSavedMeal(_ draft: SavedMealDraft) async throws -> SavedMeal

    /// Replaces the template's name, notes and components. Meals already logged don't change.
    func updateSavedMeal(_ savedMeal: SavedMeal, with draft: SavedMealDraft) async throws

    /// Deletes the template. Meals logged from it stay in the log, unlinked.
    func deleteSavedMeal(_ savedMeal: SavedMeal) async throws

    func imageURL(for savedMeal: SavedMeal) -> URL?

    /// Creates a template from a logged meal's current items. The meal itself isn't
    /// linked to it, because it wasn't logged from the template.
    @discardableResult
    func makeSavedMeal(from meal: MealEntry, name: String) async throws -> SavedMeal

    /// Logs a copy of the template. `mealType` defaults to the type suggested for `timestamp`.
    @discardableResult
    func logSavedMeal(_ savedMeal: SavedMeal, at timestamp: Date, mealType: MealType?) async throws -> MealEntry

    // MARK: Photo retention

    /// Deletes the photo files of meals logged before `cutoff`, and any photo file no
    /// record refers to. Meals, their foods and macros are kept, so the log and
    /// progress charts are unchanged. Saved meal templates keep their own photos.
    @discardableResult
    func prunePhotos(ofMealsBefore cutoff: Date) async throws -> PhotoPruneResult

    /// Yields after every saved change to stored data, wherever it was made.
    /// Each call returns an independent stream that ends when its consumer is cancelled.
    func changes() -> AsyncStream<Void>
}

/// What a photo cleanup removed.
struct PhotoPruneResult: Equatable, Sendable {
    /// Meals whose photo was removed. Their records remain.
    var mealsCleared = 0
    /// Files deleted, including orphans.
    var filesDeleted = 0
}

/// How long logged meals keep their photos.
enum PhotoRetention {
    static let days = 7

    /// Photos of meals logged before this are deleted: the same time of day, `days` ago.
    static func cutoff(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now.addingTimeInterval(-Double(days) * 86_400)
    }
}

extension PersistenceServiceProtocol {
    @discardableResult
    func pruneExpiredPhotos(now: Date = .now, calendar: Calendar = .current) async throws -> PhotoPruneResult {
        try await prunePhotos(ofMealsBefore: PhotoRetention.cutoff(now: now, calendar: calendar))
    }
}
