// Services/Configuration/GeminiKeyManager.swift

import Foundation
import Observation

/// The app's view of the user's Gemini key. Settings and Scan share one instance,
/// so saving a key in either place is seen by both. The key itself is never kept
/// here: only whether one exists and a redacted form for display.
@MainActor
@Observable
final class GeminiKeyManager {
    static let keyPageURL = URL(string: "https://aistudio.google.com/apikey")!

    private(set) var redactedKey: String?
    /// Set when the Keychain couldn't be read at launch.
    private(set) var loadError: String?

    @ObservationIgnored let store: any APIKeyStoring

    init(store: any APIKeyStoring) {
        self.store = store
        refresh()
    }

    var hasKey: Bool { redactedKey != nil }

    /// Validates, then stores the key. Surrounding whitespace from pasting is removed.
    func save(_ text: String) throws {
        let key = try AppConfiguration.validatedAPIKey(text).get()
        try store.save(key)
        refresh()
    }

    func remove() throws {
        try store.delete()
        refresh()
    }

    private func refresh() {
        do {
            redactedKey = try store.load().map(AppConfiguration.redact)
            loadError = nil
        } catch {
            redactedKey = nil
            loadError = error.localizedDescription
        }
    }
}
