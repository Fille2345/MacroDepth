// Features/ManualTracking/ManualTrackingView.swift

import SwiftUI

/// Find a food by barcode or name, choose its weight, and add it to the meal.
struct ManualTrackingView: View {
    @Bindable var viewModel: ManualTrackingViewModel
    let onAdd: (FoodItemDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.mode {
                case .barcode: BarcodeScreen(viewModel: viewModel)
                case .search: FoodSearchScreen(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .navigationDestination(item: $viewModel.selectedProduct) { product in
                FoodWeightScreen(viewModel: viewModel, product: product, onAdd: onAdd)
            }
        }
    }
}

/// Says where the values came from. Open Food Facts' licence requires crediting it.
private struct FoodDataNotice: View {
    let usesSampleData: Bool

    var body: some View {
        if usesSampleData {
            Label(
                "Sample data, not a real food database. Check values against the label before saving.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        } else {
            Text("Data from Open Food Facts (ODbL), written by volunteers. Check it against the label.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Barcode

private struct BarcodeScreen: View {
    @Bindable var viewModel: ManualTrackingViewModel
    @Environment(\.openURL) private var openURL
    @FocusState private var isTypingCode: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FoodDataNotice(usesSampleData: viewModel.usesSampleData)
                cameraArea
                lookupStatus
                typedEntry

                Button("Search by Name Instead", systemImage: "magnifyingglass") {
                    viewModel.switchMode(to: .search)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Scan Barcode")
        .task {
            await viewModel.prepareCamera()
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch viewModel.cameraState {
        case .preparing:
            placeholder { ProgressView("Starting camera…") }
        case .ready:
            BarcodeCameraView(
                isScanning: viewModel.isCameraScanning,
                onDetect: { code in Task { await viewModel.lookUpBarcode(code) } },
                onFailure: { viewModel.cameraFailed() }
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Barcode camera")
        case .denied:
            placeholder {
                VStack(spacing: 10) {
                    Text("Camera access is off, so the code can't be scanned. You can still type it below.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                .padding()
            }
        case .unavailable:
            placeholder {
                Text("The camera isn't available. Type the code below instead.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var lookupStatus: some View {
        switch viewModel.lookupState {
        case .idle:
            if viewModel.cameraState == .ready {
                Text("Hold the barcode about 20 cm from the camera, inside the frame.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .lookingUp:
            ProgressRow(title: "Looking up product…")
        case .invalidCode:
            Text("That isn't a valid barcode. Check the digits and try again.")
                .font(.footnote)
                .foregroundStyle(.red)
        case .notFound(let code):
            VStack(alignment: .leading, spacing: 8) {
                Text("No product found for \(code).")
                    .font(.subheadline.weight(.medium))
                HStack {
                    Button("Scan Again") { viewModel.resetLookup() }
                    Button("Search by Name") { viewModel.switchMode(to: .search) }
                }
                .buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Try Again") { viewModel.resetLookup() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var typedEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or type the code")
                .font(.subheadline.weight(.medium))
            HStack {
                TextField("8, 12 or 13 digits", text: $viewModel.barcodeText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTypingCode)
                Button("Look Up") {
                    isTypingCode = false
                    Task { await viewModel.lookUpBarcode(viewModel.barcodeText) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.barcodeText.isEmpty || viewModel.lookupState == .lookingUp)
            }
        }
    }
}

// MARK: - Search

private struct FoodSearchScreen: View {
    @Bindable var viewModel: ManualTrackingViewModel

    var body: some View {
        List {
            FoodDataNotice(usesSampleData: viewModel.usesSampleData)

            if let error = viewModel.searchError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Button("Try Again") { viewModel.submitSearch() }
                        .buttonStyle(.bordered)
                }
            }

            ForEach(viewModel.searchResults) { product in
                Button {
                    viewModel.selectedProduct = product
                } label: {
                    FoodResultRow(product: product)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if viewModel.isSearching {
                ProgressView("Searching…")
            } else if let query = viewModel.searchedQuery {
                if viewModel.searchResults.isEmpty && viewModel.searchError == nil {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ContentUnavailableView(
                    "Search for a food",
                    systemImage: "magnifyingglass",
                    description: Text("Type a food or brand, then tap Search on the keyboard.")
                )
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search foods"
        )
        .onSubmit(of: .search) { viewModel.submitSearch() }
        .navigationTitle("Search Food")
    }
}

private struct FoodResultRow: View {
    let product: FoodProduct

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.body)
                if let brand = product.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Per 100 g: \(NutritionFormat.grams(product.macrosPer100Grams.proteinGrams)) protein")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(NutritionFormat.kilocalories(product.macrosPer100Grams.energyKilocalories))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Weight

private struct FoodWeightScreen: View {
    @Bindable var viewModel: ManualTrackingViewModel
    let product: FoodProduct
    let onAdd: (FoodItemDraft) -> Void

    @FocusState private var isEnteringWeight: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.title3.bold())
                    if let brand = product.brand {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Weight")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        TextField("Grams", text: $viewModel.gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 110)
                            .focused($isEnteringWeight)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    if let error = viewModel.gramsError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                MacroSummaryView(macros: viewModel.entryMacros ?? .zero)

                Button {
                    if let draft = viewModel.makeDraft() { onAdd(draft) }
                } label: {
                    Label("Add to Meal", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandGreen)
                .disabled(viewModel.parsedGrams == nil)

                FoodDataNotice(usesSampleData: viewModel.usesSampleData)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Choose Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isEnteringWeight = true }
    }
}

#Preview("Search") {
    ManualTrackingView(
        viewModel: ManualTrackingViewModel(
            mode: .search,
            lookup: MockFoodLookupService(),
            permissions: MockCameraPermissionService()
        ),
        onAdd: { _ in },
        onCancel: {}
    )
}

#Preview("Barcode") {
    ManualTrackingView(
        viewModel: ManualTrackingViewModel(
            mode: .barcode,
            lookup: MockFoodLookupService(),
            permissions: MockCameraPermissionService()
        ),
        onAdd: { _ in },
        onCancel: {}
    )
}
