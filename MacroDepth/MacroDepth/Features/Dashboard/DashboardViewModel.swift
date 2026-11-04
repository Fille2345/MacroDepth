// Features/Dashboard/DashboardViewModel.swift

import Foundation
import Observation

/// Today's intake against the user's targets, kept current from persistence changes.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var profile: UserProfileDraft?
    private(set) var eaten: MacroNutrients = .zero
    private(set) var errorPresentation: ErrorPresentation?

    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let now: @MainActor () -> Date

    init(persistence: any PersistenceServiceProtocol, now: @escaping @MainActor () -> Date = { .now }) {
        self.persistence = persistence
        self.now = now
    }

    /// `nil` until a profile exists.
    var progress: DailyProgress? {
        profile.map { DailyProgress(targets: $0.targets(on: now()), eaten: eaten) }
    }

    func load() {
        do {
            profile = try persistence.currentProfile()
            eaten = try persistence.meals(on: now()).map(\.totalMacros).sum()
            errorPresentation = nil
        } catch {
            errorPresentation = ErrorPresentation(error)
        }
    }

    /// Call from the view's `.task`. Reloads whenever meals or the profile change,
    /// wherever the change was made, until the view disappears.
    func observeChanges() async {
        load()
        for await _ in persistence.changes() {
            load()
        }
    }

    func makeGoalEditor() -> OnboardingViewModel {
        OnboardingViewModel(persistence: persistence, existingProfile: profile)
    }
}
