// Features/Scan/ScanViewModel.swift

import ARKit
import Foundation
import Observation
import UIKit

/// Drives the scan flow: start scanner → top-down photo → optional angled photo
/// → optional notes → detect → estimate → review → save.
@MainActor
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case idle
        case startingScanner
        case ready
        case capturing
        /// The top-down photo is taken. The user can add an angled photo or skip it.
        case awaitingSecondaryPhoto
        case capturingSecondaryPhoto
        /// All photos are in. The user can add notes before submitting.
        case readyToAnalyze
        case detecting
        case estimating
        case review
        case saving
        case saved
        case failed(ErrorPresentation)

        var isAnalyzing: Bool {
            switch self {
            case .capturing, .capturingSecondaryPhoto, .detecting, .estimating: true
            default: false
            }
        }
    }

    static let gramStep = 5.0

    private(set) var phase: Phase = .idle
    private(set) var scannerState: ScannerState = .idle
    private(set) var permissionStatus: CameraPermissionStatus?
    private(set) var capture: DepthCapture?
    private(set) var previewImage: UIImage?
    private(set) var secondaryPreviewImage: UIImage?
    /// The angled photo is optional, so its failure is shown inline and keeps the first photo.
    private(set) var secondaryCaptureError: ErrorPresentation?
    private(set) var depthStatistics: DepthStatistics?
    private(set) var detections: [DetectedFoodItem] = []
    private(set) var drafts: [FoodItemDraft] = []
    /// A save failure keeps the review data; it is shown inline instead of replacing the screen.
    private(set) var saveError: ErrorPresentation?
    var mealType: MealType
    /// Raw text from the notes sheet. Use `normalizedNotes` when sending or saving it.
    var userNotes = ""

    let capabilities: ScannerCapabilities
    /// The session to show as the live camera feed. `nil` for the simulated scanner.
    let previewSession: ARSession?

    @ObservationIgnored private let scanner: any ARScannerServiceProtocol
    @ObservationIgnored private let nutrition: any NutritionServiceProtocol
    @ObservationIgnored private let persistence: any PersistenceServiceProtocol
    @ObservationIgnored private let permissions: any CameraPermissionProviding
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var scannerStartTask: Task<Void, Never>?
    /// Recipe notes waiting for a meal that's being analyzed or reviewed to finish.
    private var queuedNotes: String?
    /// The last recipe's text, so choosing another recipe replaces it but typed notes survive.
    @ObservationIgnored private var lastPrefilledNotes: String?

    init(
        scanner: any ARScannerServiceProtocol,
        nutrition: any NutritionServiceProtocol,
        persistence: any PersistenceServiceProtocol,
        permissions: any CameraPermissionProviding,
        now: Date = .now
    ) {
        self.scanner = scanner
        self.nutrition = nutrition
        self.persistence = persistence
        self.permissions = permissions
        self.capabilities = scanner.capabilities
        self.previewSession = (scanner as? ARScannerService)?.session
        self.mealType = .suggested(for: now)
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            scanner: dependencies.scanner,
            nutrition: dependencies.nutrition,
            persistence: dependencies.persistence,
            permissions: dependencies.cameraPermissions
        )
    }

    // MARK: Derived state

    var canCapture: Bool { phase == .ready && scannerState.isReadyToCapture }

    var canCaptureSecondaryPhoto: Bool { phase == .awaitingSecondaryPhoto && scannerState.isReadyToCapture }

    var normalizedNotes: String? { MealNotes.normalized(userNotes) }

    /// While framing the angled photo the card shows the viewfinder, not the first photo.
    var displayedImage: UIImage? {
        switch phase {
        case .awaitingSecondaryPhoto, .capturingSecondaryPhoto: nil
        default: previewImage
        }
    }

    var canReset: Bool {
        switch phase {
        case .awaitingSecondaryPhoto, .readyToAnalyze, .review, .saved, .failed: true
        default: false
        }
    }

    var hasQueuedNotes: Bool { queuedNotes != nil }

    var totalMacros: MacroNutrients { drafts.map(\.totalMacros).sum() }

    var hasPhotoOnlyEstimates: Bool {
        drafts.contains { $0.portion.source == .visualEstimate }
    }

    // MARK: Lifecycle

    /// Call from the view's `.task`. Runs until the view disappears, then stops the scanner.
    func activate() async {
        async let observation: Void = observeScannerState()
        await prepareAndStartScanner()
        await observation

        // The view went away: cancel in-flight work and release the camera.
        analysisTask?.cancel()
        scannerStartTask?.cancel()
        await scanner.stop()
    }

    // MARK: Intents

    /// Fills the notes from a recipe. A meal being analyzed or reviewed already used
    /// its notes, so changing them would mislabel it; the recipe waits for the next scan.
    func prefillNotes(_ notes: String) {
        switch phase {
        case .detecting, .estimating, .review, .saving:
            queuedNotes = notes
        case .saved:
            queuedNotes = notes
            reset()
        default:
            applyPrefilledNotes(notes)
        }
    }

    func capturePrimaryPhoto() {
        guard canCapture else { return }
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runPrimaryCapture()
        }
    }

    func captureSecondaryPhoto() {
        guard canCaptureSecondaryPhoto else { return }
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runSecondaryCapture()
        }
    }

    func skipSecondaryPhoto() {
        guard phase == .awaitingSecondaryPhoto else { return }
        secondaryCaptureError = nil
        phase = .readyToAnalyze
    }

    /// Goes back to add an angled photo after skipping, or to replace the current one.
    func returnToSecondaryPhoto() {
        guard phase == .readyToAnalyze else { return }
        phase = .awaitingSecondaryPhoto
    }

    func analyze() {
        guard phase == .readyToAnalyze, let capture else { return }
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runAnalysisPipeline(capture: capture)
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    func retry() {
        if capture != nil {
            // Analysis failed. Return to the photos and notes so the user can resubmit,
            // edit the notes, or start over if the photo itself was the problem.
            clearAnalysisResults()
            phase = .readyToAnalyze
        } else if scannerState.isReadyToCapture {
            phase = .ready
            capturePrimaryPhoto()
        } else {
            phase = .idle
            scannerStartTask?.cancel()
            scannerStartTask = Task { [weak self] in
                await self?.prepareAndStartScanner()
            }
        }
    }

    func stepGrams(for id: UUID, by delta: Double) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let newGrams = max(drafts[index].portion.grams + delta, Self.gramStep)
        drafts[index].portion = PortionCalculator.adjusted(drafts[index].portion, toGrams: newGrams)
    }

    func removeDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
        detections.removeAll { $0.id == id }
    }

    func saveMeal() async {
        guard phase == .review, !drafts.isEmpty else { return }
        saveError = nil
        phase = .saving
        let draft = MealDraft(
            timestamp: capture?.capturedAt ?? .now,
            mealType: mealType,
            items: drafts,
            imageJPEGData: capture?.imageJPEGData,
            userNotes: normalizedNotes
        )
        do {
            try await persistence.saveMeal(draft)
            phase = .saved
        } catch {
            saveError = ErrorPresentation(error)
            phase = .review
        }
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        clearCaptureResults()
        userNotes = ""
        lastPrefilledNotes = nil
        applyQueuedNotes()
        mealType = .suggested(for: .now)
        phase = phaseForCurrentScannerState()
    }

    // MARK: Private

    private func prepareAndStartScanner() async {
        guard await ensureCameraAccess() else { return }
        if phase == .idle {
            phase = .startingScanner
        }
        do {
            try await scanner.start()
        } catch is CancellationError {
            // The view disappeared while starting.
        } catch {
            phase = .failed(ErrorPresentation(error))
        }
    }

    private func ensureCameraAccess() async -> Bool {
        guard capabilities.requiresCameraAccess else { return true }
        let status = await permissions.requestAccess()
        permissionStatus = status
        if let error = status.blockingError {
            phase = .failed(ErrorPresentation(error))
            return false
        }
        return true
    }

    private func observeScannerState() async {
        for await state in scanner.stateUpdates() {
            scannerState = state
            switch state {
            case .running:
                if phase == .idle || phase == .startingScanner { phase = .ready }
            case .starting:
                if phase == .idle || phase == .ready { phase = .startingScanner }
            case .idle, .interrupted:
                if phase == .ready { phase = .startingScanner }
            case .failed(let error):
                if phase == .idle || phase == .startingScanner || phase == .ready {
                    phase = .failed(ErrorPresentation(error))
                }
            }
        }
    }

    private func runPrimaryCapture() async {
        clearCaptureResults()
        do {
            phase = .capturing
            let capture = try await scanner.capture()
            try Task.checkCancellation()
            self.capture = capture
            previewImage = UIImage(data: capture.imageJPEGData)
            depthStatistics = capture.depthMap?.statistics()
            phase = .awaitingSecondaryPhoto
        } catch is CancellationError {
            phase = phaseForCurrentScannerState()
        } catch {
            phase = .failed(ErrorPresentation(error))
        }
    }

    private func runSecondaryCapture() async {
        secondaryCaptureError = nil
        phase = .capturingSecondaryPhoto
        do {
            let imageData = try await scanner.captureSecondaryImage()
            try Task.checkCancellation()
            capture?.secondaryImageJPEGData = imageData
            secondaryPreviewImage = UIImage(data: imageData)
            phase = .readyToAnalyze
        } catch is CancellationError {
            phase = .awaitingSecondaryPhoto
        } catch {
            secondaryCaptureError = ErrorPresentation(error)
            phase = .awaitingSecondaryPhoto
        }
    }

    private func runAnalysisPipeline(capture: DepthCapture) async {
        clearAnalysisResults()
        let images = capture.allImagesJPEGData
        let notes = normalizedNotes
        do {
            phase = .detecting
            let detections = try await nutrition.detectFoodItems(in: images, userNotes: notes)
            guard !detections.isEmpty else { throw NutritionServiceError.noFoodDetected }
            self.detections = detections

            phase = .estimating
            // Per-item LiDAR volumes are computed here from Phase 3 on. Until then every
            // item takes the photo-only path, which the review screen flags.
            let volumes: [UUID: VolumeMeasurement] = [:]
            let queries = detections.map {
                NutritionQuery(id: $0.id, label: $0.label, category: $0.category, measuredVolume: volumes[$0.id])
            }
            let estimates = try await nutrition.estimateNutrition(for: queries, images: images, userNotes: notes)
            try Task.checkCancellation()

            let drafts = MealDraftBuilder.makeItems(detections: detections, estimates: estimates, volumes: volumes)
            guard !drafts.isEmpty else {
                throw NutritionServiceError.decodingFailed("no usable nutrition estimates were returned")
            }
            self.drafts = drafts
            phase = .review
        } catch is CancellationError {
            // Keep the photos and notes so the user can resubmit without retaking them.
            clearAnalysisResults()
            applyQueuedNotes()
            phase = .readyToAnalyze
        } catch {
            applyQueuedNotes()
            phase = .failed(ErrorPresentation(error))
        }
    }

    private func applyQueuedNotes() {
        guard let queuedNotes else { return }
        self.queuedNotes = nil
        applyPrefilledNotes(queuedNotes)
    }

    private func applyPrefilledNotes(_ notes: String) {
        let isBlank = userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isBlank || userNotes == lastPrefilledNotes {
            userNotes = notes
        } else {
            userNotes += "\n\n\(notes)"
        }
        lastPrefilledNotes = userNotes == notes ? notes : nil
    }

    private func clearCaptureResults() {
        capture = nil
        previewImage = nil
        secondaryPreviewImage = nil
        secondaryCaptureError = nil
        depthStatistics = nil
        clearAnalysisResults()
    }

    private func clearAnalysisResults() {
        detections = []
        drafts = []
        saveError = nil
    }

    private func phaseForCurrentScannerState() -> Phase {
        switch scannerState {
        case .running where scannerState.isReadyToCapture: .ready
        case .failed(let error): .failed(ErrorPresentation(error))
        default: .startingScanner
        }
    }
}
