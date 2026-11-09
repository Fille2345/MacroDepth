// Features/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsViewModel
    @State private var isConfirmingKeyRemoval = false
    @State private var keyRemovalError: String?

    private var isShowingKeyRemovalError: Binding<Bool> {
        Binding(get: { keyRemovalError != nil }, set: { if !$0 { keyRemovalError = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let redactedKey = viewModel.apiKeys.redactedKey {
                        LabeledContent("API key", value: redactedKey)
                    } else {
                        Label {
                            Text(viewModel.apiKeys.loadError ?? "No key saved. Add one to scan meals.")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "key.slash")
                                .foregroundStyle(.red)
                        }
                    }
                    GeminiKeyEntryRows(apiKeys: viewModel.apiKeys)
                    if viewModel.apiKeys.hasKey {
                        Button("Remove Key", role: .destructive) {
                            isConfirmingKeyRemoval = true
                        }
                    }
                    LabeledContent("Model", value: viewModel.modelID)
                    if viewModel.usesMockAnalysis {
                        LabeledContent("Analysis", value: "Mock service")
                    }
                } header: {
                    Text("Gemini")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        GeminiKeyFooter()
                        Text("Photos, depth-derived volumes and any notes you add are sent to Google's Gemini API for analysis.")
                    }
                }
                .confirmationDialog("Remove the Gemini API key?", isPresented: $isConfirmingKeyRemoval, titleVisibility: .visible) {
                    Button("Remove Key", role: .destructive) {
                        do {
                            try viewModel.apiKeys.remove()
                        } catch {
                            keyRemovalError = error.localizedDescription
                        }
                    }
                } message: {
                    Text("You'll need to add a key again before you can scan meals.")
                }
                .alert("Couldn't remove the key", isPresented: isShowingKeyRemovalError) {
                    Button("OK") { keyRemovalError = nil }
                } message: {
                    Text(keyRemovalError ?? "")
                }

                AppleHealthSection(health: viewModel.health)

                Section {
                    LabeledContent("Food database", value: viewModel.usesSampleFoodData ? "Sample data" : "Open Food Facts")
                } footer: {
                    if viewModel.usesSampleFoodData {
                        Text("Barcode and food search results are samples.")
                    } else {
                        Text("Barcodes and food searches you enter are sent to Open Food Facts. Its data is available under the Open Database License (ODbL).")
                    }
                }

                Section("Device") {
                    LabeledContent("Hardware", value: viewModel.hardwareDescription)
                    LabeledContent("Active scanner", value: viewModel.activeScannerCapabilities.summary)
                }

                Section {
                    LabeledContent("Meal log", value: viewModel.storageDescription)
                } header: {
                    Text("Storage")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Meal photos are deleted after \(PhotoRetention.days) days to save space. Your meals and their nutrition stay in the log and charts. Saved meals keep their photos.")
                        if let warning = viewModel.storageWarning {
                            Text(warning)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: viewModel.appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// Turns sync on and off and shows how the last sync went.
private struct AppleHealthSection: View {
    let health: HealthSyncCoordinator
    @State private var isEnabling = false

    var body: some View {
        Section {
            if health.isAvailable {
                Toggle(isOn: Binding(
                    get: { health.isEnabled },
                    set: { isOn in
                        if isOn {
                            isEnabling = true
                            Task {
                                await health.enable()
                                isEnabling = false
                            }
                        } else {
                            health.disable()
                        }
                    }
                )) {
                    Label("Sync with Apple Health", systemImage: "heart.text.square")
                }
                .disabled(isEnabling)
                statusRow
            } else {
                Label("Apple Health isn't available on this device.", systemImage: "heart.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Reads your body weight for the progress charts; a weight you enter here wins for its day. Saves each meal's calories, protein, carbohydrates (including fibre), fat and fibre from the last \(HealthSyncCoordinator.mealWindowDays) days, and keeps them up to date. Turning sync off leaves data already in Health there.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch health.status {
        case .off:
            EmptyView()
        case .syncing:
            LabeledContent("Status") {
                ProgressView()
            }
        case .synced(let date):
            LabeledContent("Last synced", value: date.formatted(date: .omitted, time: .shortened))
        case .failed(let message):
            Label {
                Text(message)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview("Key saved") {
    SettingsView(viewModel: SettingsViewModel(dependencies: .makePreview()))
}

#Preview("Missing key") {
    SettingsView(
        viewModel: SettingsViewModel(
            dependencies: .makePreview(apiKey: nil)
        )
    )
}
