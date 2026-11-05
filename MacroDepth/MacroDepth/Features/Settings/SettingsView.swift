// Features/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch viewModel.geminiStatus {
                    case .configured(let modelID, let redactedKey):
                        LabeledContent("Model", value: modelID)
                        LabeledContent("API key", value: redactedKey)
                    case .misconfigured(let message):
                        Label {
                            Text(message)
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "key.slash")
                                .foregroundStyle(.red)
                        }
                    }
                    if viewModel.usesMockAnalysis {
                        LabeledContent("Analysis", value: "Mock service")
                    }
                } header: {
                    Text("Gemini")
                } footer: {
                    Text("Photos, depth-derived volumes and any notes you add are sent to Google's Gemini API for analysis.")
                }

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
                    if let warning = viewModel.storageWarning {
                        Text(warning)
                            .foregroundStyle(.red)
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

#Preview("Configured") {
    SettingsView(viewModel: SettingsViewModel(dependencies: .makePreview()))
}

#Preview("Missing key") {
    SettingsView(
        viewModel: SettingsViewModel(
            dependencies: .makePreview(configuration: .failure(.emptyValue(key: AppConfiguration.apiKeyInfoKey)))
        )
    )
}
