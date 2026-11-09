// Services/Health/HealthStoreProtocol.swift

import Foundation

/// The parts of Apple Health the app uses. `HealthKitStore` is the live implementation;
/// `InMemoryHealthStore` stands in for previews and tests.
protocol HealthStoreProtocol: Sendable {
    var isAvailable: Bool { get }

    /// Shows the Health permission sheet the first time; later calls return at once.
    func requestAuthorization() async throws

    /// The last body weight of each day in the interval. Days without one are left out.
    func dailyBodyMass(in interval: DateInterval, calendar: Calendar) async throws -> [DailyWeight]

    /// Meals this app wrote with a timestamp in the interval: meal id → fingerprint.
    func mealFingerprints(in interval: DateInterval) async throws -> [UUID: String]

    /// Writes meals, replacing any earlier version with the same id.
    func saveMeals(_ meals: [HealthMealRecord]) async throws

    /// Removes the meals this app wrote with these ids.
    func deleteMeals(ids: Set<UUID>) async throws
}

/// For previews and tests. Records what was written.
final class InMemoryHealthStore: HealthStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var weights: [DailyWeight]
    private var meals: [UUID: HealthMealRecord] = [:]
    private var authorizationError: HealthSyncError?
    private var writeError: HealthSyncError?
    private var saveCalls = 0

    let isAvailable: Bool

    init(isAvailable: Bool = true, weights: [DailyWeight] = []) {
        self.isAvailable = isAvailable
        self.weights = weights
    }

    var savedMeals: [UUID: HealthMealRecord] { lock.withLock { meals } }
    var saveCallCount: Int { lock.withLock { saveCalls } }

    func setWeights(_ weights: [DailyWeight]) { lock.withLock { self.weights = weights } }
    func failAuthorization(with error: HealthSyncError?) { lock.withLock { authorizationError = error } }
    func failWrites(with error: HealthSyncError?) { lock.withLock { writeError = error } }

    /// As if the user deleted a meal in the Health app.
    func removeMealExternally(id: UUID) { lock.withLock { _ = meals.removeValue(forKey: id) } }

    func requestAuthorization() async throws {
        if let error = lock.withLock({ authorizationError }) { throw error }
    }

    func dailyBodyMass(in interval: DateInterval, calendar: Calendar) async throws -> [DailyWeight] {
        lock.withLock { weights.filter { interval.contains($0.day) } }
    }

    func mealFingerprints(in interval: DateInterval) async throws -> [UUID: String] {
        lock.withLock {
            meals.values.filter { interval.contains($0.timestamp) }
                .reduce(into: [:]) { $0[$1.id] = $1.fingerprint }
        }
    }

    func saveMeals(_ records: [HealthMealRecord]) async throws {
        try lock.withLock {
            if let writeError { throw writeError }
            saveCalls += 1
            for record in records { meals[record.id] = record }
        }
    }

    func deleteMeals(ids: Set<UUID>) async throws {
        try lock.withLock {
            if let writeError { throw writeError }
            for id in ids { meals.removeValue(forKey: id) }
        }
    }
}
