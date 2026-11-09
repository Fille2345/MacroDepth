// Services/Health/HealthSyncCoordinator.swift

import Foundation
import Observation

/// Keeps Apple Health and the meal log in step while sync is on.
///
/// - Body weight flows in: each day's last Health reading becomes a weigh-in, so the
///   Progress charts show it. A weight entered in the app wins for its day.
/// - Meals flow out: each meal from the last `mealWindowDays` is written as one food
///   entry and kept up to date as meals are edited or deleted.
///
/// A sync runs when sync is turned on, when the app becomes active and after every
/// change to stored data. Requests during a sync are coalesced into one more pass.
@MainActor
@Observable
final class HealthSyncCoordinator {
    enum Status: Equatable {
        case off
        case syncing
        case synced(Date)
        case failed(String)
    }

    static let enabledDefaultsKey = "healthSyncEnabled"
    static let weightWindowDays = 180
    static let mealWindowDays = 30

    private(set) var isEnabled: Bool
    private(set) var status: Status = .off

    let isAvailable: Bool

    @ObservationIgnored private let store: any HealthStoreProtocol
    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false

    init(
        store: any HealthStoreProtocol,
        persistence: any PersistenceServiceProtocol,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        debounce: Duration = .milliseconds(500),
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.store = store
        self.persistence = persistence
        self.defaults = defaults
        self.calendar = calendar
        self.debounce = debounce
        self.now = now
        isAvailable = store.isAvailable
        isEnabled = store.isAvailable && defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    // MARK: Intents

    /// Asks for Health access, then turns sync on and runs the first sync.
    func enable() async {
        guard isAvailable else {
            status = .failed(HealthSyncError.unavailable.fullDescription)
            return
        }
        do {
            try await store.requestAuthorization()
        } catch {
            status = .failed(Self.describe(error))
            return
        }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledDefaultsKey)
        requestSync()
    }

    /// Stops syncing. Data already in Health stays there. Weigh-ins imported from
    /// Health become ordinary weigh-ins the user can edit or delete.
    func disable() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledDefaultsKey)
        syncTask?.cancel()
        syncTask = nil
        needsAnotherPass = false
        status = .off
        do {
            try persistence.releaseHealthWeights()
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    func requestSync() {
        guard isEnabled else { return }
        if syncTask != nil {
            needsAnotherPass = true
            return
        }
        syncTask = Task { [weak self] in
            await self?.runSyncPasses()
        }
    }

    /// Call from a long-lived `.task`. Syncs after every stored change.
    func observeChanges() async {
        requestSync()
        for await _ in persistence.changes() {
            requestSync()
        }
    }

    /// Waits until no sync is running. For tests.
    func waitForSync() async {
        while let task = syncTask {
            await task.value
        }
    }

    // MARK: Private

    private func runSyncPasses() async {
        repeat {
            needsAnotherPass = false
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled, isEnabled else { break }
            status = .syncing
            do {
                try await syncOnce()
                status = .synced(now())
            } catch is CancellationError {
                break
            } catch {
                status = .failed(Self.describe(error))
            }
        } while needsAnotherPass && isEnabled && !Task.isCancelled
        syncTask = nil
    }

    private func syncOnce() async throws {
        let date = now()

        // Weight in. Importing saves only if something changed, so the change it
        // broadcasts can't cause an endless loop of syncs.
        let weightStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -Self.weightWindowDays, to: date) ?? date)
        let weightInterval = DateInterval(start: weightStart, end: max(date, weightStart))
        let weights = try await store.dailyBodyMass(in: weightInterval, calendar: calendar)
        try Task.checkCancellation()
        try persistence.importHealthWeights(weights, covering: weightInterval)

        // Meals out. Compare what Health has against the log by fingerprint.
        let mealStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -Self.mealWindowDays, to: date) ?? date)
        let mealEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let mealInterval = DateInterval(start: mealStart, end: mealEnd)
        let local = try persistence.meals(in: mealInterval).map {
            HealthMealRecord(id: $0.id, timestamp: $0.timestamp, mealType: $0.mealType, macros: $0.totalMacros)
        }
        let remote = try await store.mealFingerprints(in: mealInterval)
        try Task.checkCancellation()

        let localFingerprints = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0.fingerprint) })
        let stale = Set(remote.compactMap { id, fingerprint in localFingerprints[id] == fingerprint ? nil : id })
        let toSave = local.filter { remote[$0.id] != $0.fingerprint }

        if !stale.isEmpty {
            try await store.deleteMeals(ids: stale)
        }
        if !toSave.isEmpty {
            try await store.saveMeals(toSave)
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.fullDescription ?? error.localizedDescription
    }
}
