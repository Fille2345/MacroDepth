// Features/Settings/GeminiKeyViews.swift

import SwiftUI

/// A secure field plus Save button for the Gemini key. Used inside a `Form`
/// in Settings and in the prompt Scan shows when no key is saved.
struct GeminiKeyEntryRows: View {
    let apiKeys: GeminiKeyManager
    var saveTitle: LocalizedStringKey = "Save Key"
    var onSaved: () -> Void = {}

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(apiKeys.hasKey ? "Paste a new key to replace it" : "Paste your Gemini API key", text: $text)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(save)
            .onChange(of: text) { errorMessage = nil }

        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Button(saveTitle, action: save)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        do {
            try apiKeys.save(text)
            text = ""
            errorMessage = nil
            isFocused = false
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.fullDescription ?? error.localizedDescription
        }
    }
}

/// Shown when the user tries to scan without a key.
struct GeminiKeySheet: View {
    let apiKeys: GeminiKeyManager
    let onSaved: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GeminiKeyEntryRows(apiKeys: apiKeys, saveTitle: "Save and Continue", onSaved: onSaved)
                } header: {
                    Text("Gemini API key")
                } footer: {
                    GeminiKeyFooter()
                }
            }
            .navigationTitle("Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct GeminiKeyFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scanning uses Google's Gemini API with your own key. It's stored in this device's Keychain and only sent to Google.")
            Link("Get a free key in Google AI Studio", destination: GeminiKeyManager.keyPageURL)
        }
    }
}

#Preview("Prompt") {
    GeminiKeySheet(apiKeys: GeminiKeyManager(store: InMemoryAPIKeyStore()), onSaved: {}, onCancel: {})
}
