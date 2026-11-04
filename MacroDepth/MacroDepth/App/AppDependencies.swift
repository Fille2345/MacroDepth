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
    let persistence: any PersistenceServiceProtocol
    let cameraPermissions: any CameraPermissionProviding
    let configuration: Result<AppConfiguration, ConfigurationError>
    /// Set when the persistent store couldn't open and an in-memory store is used.
    let persistenceWarning: String?

    init(
        mode: Mode,
        hardwareCapabilities: ScannerCapabilities,
        scanner: any ARScannerServiceProtocol,
        nutrition: any NutritionServiceProtocol,
        persistence: any PersistenceServiceProtocol,
        cameraPermissions: any CameraPermissionProviding,
        configuration: Result<AppConfiguration, ConfigurationError>,
        persistenceWarning: String? = nil
    ) {
        self.mode = mode
        self.hardwareCapabilities = hardwareCapabilities
        self.scanner = scanner
        self.nutrition = nutrition
        self.persistence = persistence
        self.cameraPermissions = cameraPermissions
        self.configuration = configuration
        self.persistenceWarning = persistenceWarning
    }

    static func makeForCurrentProcess() -> AppDependencies {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return makePreview()
        }
        return makeLive()
    }

    /// Phase 1 live graph: real persistence, permissions, configuration and
    /// hardware detection. Scanning uses the simulated scanner and analysis uses
    /// the mock service until `ARScannerService` (Phase 2) and
    /// `GeminiNutritionService` (Phase 4) are added here.
    static func makeLive() -> AppDependencies {
        let persistence: SwiftDataPersistenceService
        var persistenceWarning: String?
        do {
            persistence = try SwiftDataPersistenceService.makePersistent()
        } catch {
            persistenceWarning = "Your meal log couldn't be opened, so meals are kept only until the app quits. (\(error.localizedDescription))"
            persistence = makeInMemoryStoreOrTerminate()
        }

        return AppDependencies(
            mode: .live,
            hardwareCapabilities: DeviceCapabilityProbe.currentHardware(),
            scanner: SimulatedScannerService(),
            nutrition: MockNutritionService(),
            persistence: persistence,
            cameraPermissions: SystemCameraPermissionService(),
            configuration: AppConfiguration.load(),
            persistenceWarning: persistenceWarning
        )
    }

    static func makePreview(
        scannerCapabilities: ScannerCapabilities = .simulated,
        nutritionBehavior: MockNutritionService.Behavior = .success,
        seedSampleMeals: Bool = true,
        configuration: Result<AppConfiguration, ConfigurationError> = .success(
            AppConfiguration(apiKey: "AIzaPreviewKey000000000000", modelID: AppConfiguration.defaultModelID)
        )
    ) -> AppDependencies {
        let persistence = makeInMemoryStoreOrTerminate()
        if seedSampleMeals {
            persistence.seedSampleMeals()
        }
        return AppDependencies(
            mode: .preview,
            hardwareCapabilities: scannerCapabilities,
            scanner: SimulatedScannerService(capabilities: scannerCapabilities),
            nutrition: MockNutritionService(behavior: nutritionBehavior, latency: .milliseconds(400)),
            persistence: persistence,
            cameraPermissions: MockCameraPermissionService(),
            configuration: configuration
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
