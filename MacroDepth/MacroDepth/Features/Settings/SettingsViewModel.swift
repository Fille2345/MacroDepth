// Features/Settings/SettingsViewModel.swift

import Foundation

/// The Gemini key, plus read-only diagnostics: hardware and storage. The key can
/// change at any time, so it's read through the shared `GeminiKeyManager`;
/// everything else is fixed at launch.
@MainActor
struct SettingsViewModel {
    let apiKeys: GeminiKeyManager
    let modelID: String
    let hardwareCapabilities: ScannerCapabilities
    let activeScannerCapabilities: ScannerCapabilities
    let usesMockAnalysis: Bool
    let usesSampleFoodData: Bool
    let storageDescription: String
    let storageWarning: String?
    let appVersion: String

    init(dependencies: AppDependencies, bundle: Bundle = .main) {
        apiKeys = dependencies.apiKeys
        modelID = dependencies.modelID
        hardwareCapabilities = dependencies.hardwareCapabilities
        activeScannerCapabilities = dependencies.scanner.capabilities
        usesMockAnalysis = dependencies.nutrition is MockNutritionService
        usesSampleFoodData = dependencies.foodLookup is MockFoodLookupService
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
