// App/AppDependencies.swift

import Foundation

/// Composition root. Builds the live or preview service graph once at launch;
/// view models receive the individual services through their initializers.
@MainActor
final class AppDependencies {
    enum Mode: Sendable {
        case live
        case preview
    }

    let mode: Mode
    /// What the device hardware supports, independent of the scanner in use.
    let hardwareCapabilities: ScannerCapabilities
    let scanner: any ARScannerServiceProtocol
    let nutrition: any NutritionServiceProtocol
    let foodLookup: any FoodLookupServiceProtocol
    let persistence: any PersistenceServiceProtocol
    let cameraPermissions: any CameraPermissionProviding
    /// The user's Gemini key, shared by Settings and Scan.
    let apiKeys: GeminiKeyManager
    let modelID: String
    /// Set when the persistent store couldn't open and an in-memory store is used.
    let persistenceWarning: String?

    init(
        mode: Mode,
        hardwareCapabilities: ScannerCapabilities,
        scanner: any ARScannerServiceProtocol,
        nutrition: any NutritionServiceProtocol,
        foodLookup: any FoodLookupServiceProtocol = MockFoodLookupService(),
        persistence: any PersistenceServiceProtocol,
        cameraPermissions: any CameraPermissionProviding,
        apiKeys: GeminiKeyManager,
        modelID: String = AppConfiguration.defaultModelID,
        persistenceWarning: String? = nil
    ) {
        self.mode = mode
        self.hardwareCapabilities = hardwareCapabilities
        self.scanner = scanner
        self.nutrition = nutrition
        self.foodLookup = foodLookup
        self.persistence = persistence
        self.cameraPermissions = cameraPermissions
        self.apiKeys = apiKeys
        self.modelID = modelID
        self.persistenceWarning = persistenceWarning
    }

    static func makeForCurrentProcess() -> AppDependencies {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return makePreview()
        }
        return makeLive()
    }

    /// Live graph: real persistence, permissions, hardware detection, scanning, and
    /// Gemini analysis with the key the user saves in Settings.
    static func makeLive() -> AppDependencies {
        let persistence: SwiftDataPersistenceService
        var persistenceWarning: String?
        do {
            persistence = try SwiftDataPersistenceService.makePersistent()
        } catch {
            persistenceWarning = "Your meal log couldn't be opened, so meals are kept only until the app quits. (\(error.localizedDescription))"
            persistence = makeInMemoryStoreOrTerminate()
        }

        let hardware = DeviceCapabilityProbe.currentHardware()
        let keyStore = KeychainAPIKeyStore()
        let modelID = AppConfiguration.modelID()
        return AppDependencies(
            mode: .live,
            hardwareCapabilities: hardware,
            scanner: makeScanner(for: hardware),
            nutrition: KeyedGeminiNutritionService(store: keyStore, modelID: modelID),
            foodLookup: OpenFoodFactsService(),
            persistence: persistence,
            cameraPermissions: SystemCameraPermissionService(),
            apiKeys: GeminiKeyManager(store: keyStore),
            modelID: modelID,
            persistenceWarning: persistenceWarning
        )
    }

    /// Real hardware (with or without LiDAR) uses ARKit. The Simulator has no camera,
    /// so it uses the synthetic scene.
    static func makeScanner(for hardware: ScannerCapabilities) -> any ARScannerServiceProtocol {
        hardware.requiresCameraAccess
            ? ARScannerService(capabilities: hardware)
            : SimulatedScannerService(capabilities: hardware)
    }

    static func makePreview(
        scannerCapabilities: ScannerCapabilities = .simulated,
        nutritionBehavior: MockNutritionService.Behavior = .success,
        seedSampleMeals: Bool = true,
        seedSampleProfile: Bool = true,
        seedSampleProgress: Bool = false,
        apiKey: String? = "AIzaPreviewKey000000000000"
    ) -> AppDependencies {
        let persistence = makeInMemoryStoreOrTerminate()
        if seedSampleMeals {
            persistence.seedSampleMeals()
        }
        if seedSampleProfile {
            persistence.seedSampleProfile()
        }
        if seedSampleProgress {
            persistence.seedSampleProgress()
        }
        return AppDependencies(
            mode: .preview,
            hardwareCapabilities: scannerCapabilities,
            scanner: SimulatedScannerService(capabilities: scannerCapabilities),
            nutrition: MockNutritionService(behavior: nutritionBehavior, latency: .milliseconds(400)),
            persistence: persistence,
            cameraPermissions: MockCameraPermissionService(),
            apiKeys: GeminiKeyManager(store: InMemoryAPIKeyStore(key: apiKey))
        )
    }

    /// An in-memory SwiftData container uses a fixed schema and no disk, so
    /// failure means SwiftData itself is unusable and the app cannot work.
    private static func makeInMemoryStoreOrTerminate() -> SwiftDataPersistenceService {
        do {
            return try SwiftDataPersistenceService.makeInMemory()
        } catch {
            fatalError("SwiftData could not create an in-memory store: \(error)")
        }
    }
}
