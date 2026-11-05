// Features/Scan/ScanView.swift

import ARKit
import SwiftUI

struct ScanView: View {
    @Bindable var viewModel: ScanViewModel
    @Environment(\.openURL) private var openURL
    @State private var isEditingNotes = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CapturePreviewCard(
                        image: viewModel.displayedImage,
                        previewSession: viewModel.previewSession,
                        detections: viewModel.detections,
                        scannerState: viewModel.scannerState,
                        capabilities: viewModel.capabilities,
                        depthStatistics: viewModel.depthStatistics
                    )
                    phaseContent
                }
                .padding()
            }
            .navigationTitle("Scan")
            .toolbar {
                if viewModel.canReset {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Scan", systemImage: "arrow.counterclockwise") {
                            viewModel.reset()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingNotes) {
            MealNotesSheet(notes: $viewModel.userNotes)
        }
        .task {
            await viewModel.activate()
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .idle, .startingScanner:
            ProgressRow(title: viewModel.scannerState.displayText)
        case .ready:
            captureControls
        case .capturing:
            ProgressRow(title: "Capturing frame…", onCancel: { viewModel.cancelAnalysis() })
        case .awaitingSecondaryPhoto:
            secondaryPhotoControls
        case .capturingSecondaryPhoto:
            ProgressRow(title: "Capturing angled photo…", onCancel: { viewModel.cancelAnalysis() })
        case .readyToAnalyze:
            submissionControls
        case .detecting:
            ProgressRow(title: "Identifying food…", onCancel: { viewModel.cancelAnalysis() })
        case .measuring:
            ProgressRow(title: "Measuring portions…", onCancel: { viewModel.cancelAnalysis() })
        case .estimating:
            ProgressRow(title: "Estimating nutrition…", onCancel: { viewModel.cancelAnalysis() })
        case .review, .saving:
            reviewContent
        case .saved:
            savedContent
        case .failed(let presentation):
            ErrorCard(
                presentation: presentation,
                onRetry: { viewModel.retry() },
                onOpenSettings: { openSystemSettings() }
            )
        }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(captureHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if viewModel.normalizedNotes != nil {
                Label("Your notes will be sent with the photos. You can edit them after capturing.", systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                viewModel.capturePrimaryPhoto()
            } label: {
                Label("Capture Plate", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canCapture)
        }
    }

    private var secondaryPhotoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapturedPhotosRow(primary: viewModel.previewImage, secondary: viewModel.secondaryPreviewImage)
            Text("Add an angled photo?")
                .font(.headline)
            Text("Tilt the phone to about 45° so the height and texture of the food are visible. One photo is often enough, so you can skip this.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let error = viewModel.secondaryCaptureError {
                ErrorCard(
                    presentation: error,
                    onRetry: { viewModel.captureSecondaryPhoto() },
                    onOpenSettings: { openSystemSettings() }
                )
            }

            Button {
                viewModel.captureSecondaryPhoto()
            } label: {
                Label("Take Angled Photo", systemImage: "camera.rotate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canCaptureSecondaryPhoto)

            Button {
                viewModel.skipSecondaryPhoto()
            } label: {
                Text("Skip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var submissionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapturedPhotosRow(primary: viewModel.previewImage, secondary: viewModel.secondaryPreviewImage)

            Button {
                viewModel.returnToSecondaryPhoto()
            } label: {
                Label(
                    viewModel.secondaryPreviewImage == nil ? "Add Angled Photo" : "Retake Angled Photo",
                    systemImage: "camera.rotate"
                )
            }
            .buttonStyle(.borderless)

            Button {
                isEditingNotes = true
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text(viewModel.normalizedNotes ?? MealNotesSheet.placeholder)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(viewModel.normalizedNotes == nil ? .secondary : .primary)
                    Spacer()
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.analyze()
            } label: {
                Label("Analyze Meal", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var captureHint: String {
        if viewModel.capabilities.canMeasureVolume {
            "Hold the phone 30–50 cm above the plate, looking straight down."
        } else {
            "No depth sensor available. Portions will be estimated from the photo, and you can adjust them afterwards."
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Meal", selection: $viewModel.mealType) {
                ForEach(MealType.allCases) { mealType in
                    Text(mealType.displayName).tag(mealType)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.usesSampleAnalysis {
                Label(
                    "Sample data, not your photo. Add a Gemini API key to analyze real meals.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            MacroSummaryView(macros: viewModel.totalMacros)

            if viewModel.hasUnestimatedItems {
                Label(
                    "Some items found on the plate couldn't be estimated, so this total may be too low.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if let notes = viewModel.normalizedNotes {
                Label(notes, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if viewModel.hasQueuedNotes {
                Label("Your recipe will be used for your next scan.", systemImage: "fork.knife")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasPhotoOnlyEstimates {
                Label(
                    "Some portions were estimated from the photo only. Check the weights before saving.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.drafts) { draft in
                    FoodDraftRow(
                        draft: draft,
                        onIncrement: { viewModel.stepGrams(for: draft.id, by: ScanViewModel.gramStep) },
                        onDecrement: { viewModel.stepGrams(for: draft.id, by: -ScanViewModel.gramStep) },
                        onRemove: { viewModel.removeDraft(id: draft.id) }
                    )
                    if draft.id != viewModel.drafts.last?.id {
                        Divider().padding(.leading)
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            if let saveError = viewModel.saveError {
                ErrorCard(
                    presentation: saveError,
                    onRetry: { Task { await viewModel.saveMeal() } },
                    onOpenSettings: { openSystemSettings() }
                )
            }

            Button {
                Task { await viewModel.saveMeal() }
            } label: {
                Group {
                    if viewModel.phase == .saving {
                        ProgressView()
                    } else {
                        Label("Save Meal", systemImage: "checkmark.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.drafts.isEmpty || viewModel.phase == .saving)
        }
    }

    private var savedContent: some View {
        VStack(spacing: 12) {
            Label("Meal saved to your log", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Button("Scan Another Meal") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Subviews

private struct CapturePreviewCard: View {
    let image: UIImage?
    let previewSession: ARSession?
    let detections: [DetectedFoodItem]
    let scannerState: ScannerState
    let capabilities: ScannerCapabilities
    let depthStatistics: DepthStatistics?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        DetectionOverlayView(detections: detections)
                    }
                    .accessibilityLabel("Captured photo of the plate")
            } else if let previewSession {
                // Matches the upright 3:4 photo, so what's visible is what gets captured.
                Color.black
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        ARCameraPreview(session: previewSession)
                    }
                    .accessibilityLabel("Live camera view")
            } else {
                // Simulated scanner: there's no camera feed to show.
                Rectangle()
                    .fill(Color.black.gradient)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 44, weight: .light))
                            Text(scannerState.displayText)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(capabilities.summary, systemImage: capabilities.systemImage)
                if let depthStatistics {
                    Label(
                        "Depth \(NutritionFormat.centimeters(fromMeters: depthStatistics.minimumMeters))–\(NutritionFormat.centimeters(fromMeters: depthStatistics.maximumMeters))",
                        systemImage: "ruler"
                    )
                }
                if showsTrackingStatus {
                    Text(scannerState.displayText)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// On the live feed there's no placeholder text, so surface tracking problems here.
    private var showsTrackingStatus: Bool {
        image == nil && previewSession != nil && scannerState != .running(.normal)
    }
}

private struct CapturedPhotosRow: View {
    let primary: UIImage?
    let secondary: UIImage?

    var body: some View {
        HStack(spacing: 8) {
            thumbnail(primary, label: "Top-down")
            if let secondary {
                thumbnail(secondary, label: "Angled")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ image: UIImage?, label: LocalizedStringKey) -> some View {
        if let image {
            VStack(spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct MealNotesSheet: View {
    static let placeholder = "Add notes or paste recipe..."

    @Binding var notes: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $notes)
                    .focused($isFocused)
                    .accessibilityLabel(Text(Self.placeholder))
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text(Self.placeholder)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(notes.count > MealNotes.maximumLength ? .red : .secondary)
            }
            .padding()
            .navigationTitle("Meal Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private var footer: String {
        if notes.count > MealNotes.maximumLength {
            return "Only the first \(MealNotes.maximumLength.formatted()) characters will be used."
        }
        return "Cooking oils, cuts of meat or preparation details help estimate hidden fats."
    }
}

private struct FoodDraftRow: View {
    let draft: FoodItemDraft
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name)
                        .font(.headline)
                    Text("\(draft.portion.source.displayName) · \(NutritionFormat.percent(draft.portion.confidence)) confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(NutritionFormat.kilocalories(draft.totalMacros.energyKilocalories))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(draft.name)")
            }

            Stepper(onIncrement: onIncrement, onDecrement: onDecrement) {
                Text(NutritionFormat.grams(draft.portion.grams))
                    .font(.body.monospacedDigit())
            }

            if let size = draft.measuredSize {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Size (W × L × H): \(NutritionFormat.dimensions(size))")
                    Text("Volume: \(NutritionFormat.volume(size.measurement)) · \(size.shape.displayName)")
                    if let density = draft.portion.densityGramsPerCubicCentimeter {
                        Text("Density: \(NutritionFormat.density(density))")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Simulated LiDAR") {
    ScanView(viewModel: ScanViewModel(dependencies: .makePreview()))
}

#Preview("No depth sensor") {
    ScanView(viewModel: ScanViewModel(dependencies: .makePreview(scannerCapabilities: .simulatedWithoutDepth)))
}

#Preview("Analysis offline") {
    ScanView(viewModel: ScanViewModel(dependencies: .makePreview(nutritionBehavior: .failure(.offline))))
}
