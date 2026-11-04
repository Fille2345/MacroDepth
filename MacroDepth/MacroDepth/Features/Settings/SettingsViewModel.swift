// Features/Settings/SettingsViewModel.swift

import Foundation

/// Read-only diagnostics: configuration, hardware and storage. Everything is
/// fixed at launch, so a plain value type is enough.
@MainActor
struct SettingsViewModel {
    enum GeminiStatus: Equatable {
        case configured(modelID: String, redactedKey: String)
        case misconfigured(message: String)
    }

    let geminiStatus: GeminiStatus
    let hardwareCapabilities: ScannerCapabilities
    let activeScannerCapabilities: ScannerCapabilities
    let usesMockAnalysis: Bool
    let storageDescription: String
    let storageWarning: String?
    let appVersion: String

    init(dependencies: AppDependencies, bundle: Bundle = .main) {
        switch dependencies.configuration {
        case .success(let configuration):
            geminiStatus = .configured(modelID: configuration.modelID, redactedKey: configuration.redactedAPIKey)
        case .failure(let error):
            geminiStatus = .misconfigured(message: error.fullDescription)
        }
        hardwareCapabilities = dependencies.hardwareCapabilities
        activeScannerCapabilities = dependencies.scanner.capabilities
        usesMockAnalysis = dependencies.nutrition is MockNutritionService
        storageWarning = dependencies.persistenceWarning
        switch dependencies.mode {
        case .preview: storageDescription = "In memory (preview)"
        case .live: storageDescription = dependencies.persistenceWarning == nil ? "On device" : "In memory (fallback)"
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        appVersion = "\(version) (\(build))"
    }

    var hardwareDescription: String {
        switch hardwareCapabilities.depthSource {
        case .lidar: "LiDAR available"
        case .simulated: "Simulator (no camera)"
        case .none: hardwareCapabilities.supportsWorldTracking ? "No LiDAR — photo estimates" : "AR not supported"
        }
    }
}
