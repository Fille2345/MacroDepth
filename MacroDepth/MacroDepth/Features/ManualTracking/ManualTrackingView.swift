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
    var isGeneric = false

    var body: some View {
        if isGeneric {
            Text("Typical values from USDA FoodData Central. Individual foods vary.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if usesSampleData {
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
            if !viewModel.hasSearchText {
                rememberedSections
            }

            let genericResults = viewModel.genericResults
            if !genericResults.isEmpty {
                Section {
                    ForEach(genericResults) { product in
                        resultButton(product)
                    }
                } header: {
                    Text("Whole Foods")
                } footer: {
                    FoodDataNotice(usesSampleData: false, isGeneric: true)
                }
            }

            if viewModel.hasSearchText {
                Section {
                    packagedProducts
                } header: {
                    Text("Packaged Products")
                } footer: {
                    FoodDataNotice(usesSampleData: viewModel.usesSampleData)
                }
            }
        }
        .overlay {
            if !viewModel.hasSearchText && !viewModel.hasRememberedFoods {
                ContentUnavailableView(
                    "Search for a food",
                    systemImage: "magnifyingglass",
                    description: Text("Whole foods appear as you type, in English or Swedish. Tap Search on the keyboard to include packaged products.")
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

    /// Favorites and recent foods, for adding a usual food in two taps.
    @ViewBuilder
    private var rememberedSections: some View {
        let remembered = viewModel.remembered
        if !remembered.favorites.isEmpty {
            Section("Favorites") {
                ForEach(remembered.favorites) { food in
                    rememberedButton(food)
                        .swipeActions {
                            Button("Unfavorite", systemImage: "star.slash") {
                                viewModel.toggleFavorite(food.product)
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        if !remembered.recents.isEmpty {
            Section {
                ForEach(remembered.recents) { food in
                    rememberedButton(food)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                viewModel.forgetRecent(food)
                            }
                            Button("Favorite", systemImage: "star") {
                                viewModel.toggleFavorite(food.product)
                            }
                            .tint(.yellow)
                        }
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Swipe left on a food to favorite or remove it.")
            }
        }
        if let error = viewModel.rememberError {
            Section {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func rememberedButton(_ food: RememberedFood) -> some View {
        Button {
            viewModel.selectedProduct = food.product
        } label: {
            FoodResultRow(product: food.product, lastGrams: food.lastGrams, isFavorite: food.isFavorite)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var packagedProducts: some View {
        if viewModel.isSearching {
            ProgressRow(title: "Searching Open Food Facts…")
        } else if let error = viewModel.searchError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Try Again") { viewModel.submitSearch() }
                    .buttonStyle(.bordered)
            }
        } else if !viewModel.searchResults.isEmpty {
            ForEach(viewModel.searchResults) { product in
                resultButton(product)
            }
        } else if viewModel.hasSearchedCurrentText {
            Text("No packaged products found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("Tap Search on the keyboard to look for packaged products.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func resultButton(_ product: FoodProduct) -> some View {
        Button {
            viewModel.selectedProduct = product
        } label: {
            FoodResultRow(product: product)
        }
        .buttonStyle(.plain)
    }
}

private struct FoodResultRow: View {
    let product: FoodProduct
    /// For a remembered food: the weight added last time.
    var lastGrams: Double? = nil
    var isFavorite = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                    Text(product.name)
                        .font(.body)
                }
                if let lastGrams {
                    Text("Last time \(NutritionFormat.grams(lastGrams)) · \(NutritionFormat.kilocalories(product.macrosPer100Grams.forPortion(grams: lastGrams).energyKilocalories))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if product.isGeneric {
                    Text("Whole food")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.brandGreen)
                } else if let brand = product.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if lastGrams == nil {
                    Text("Per 100 g: \(NutritionFormat.grams(product.macrosPer100Grams.proteinGrams)) protein")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if lastGrams == nil {
                Text(NutritionFormat.kilocalories(product.macrosPer100Grams.energyKilocalories))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                    if let draft = viewModel.addEntry() { onAdd(draft) }
                } label: {
                    Label("Add to Meal", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandGreen)
                .disabled(viewModel.parsedGrams == nil)

                FoodDataNotice(usesSampleData: viewModel.usesSampleData, isGeneric: product.isGeneric)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Choose Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let isFavorite = viewModel.isFavorite(product)
                Button {
                    viewModel.toggleFavorite(product)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .accentColor)
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .onAppear { isEnteringWeight = true }
    }
}

#Preview("Search") {
    let persistence = AppDependencies.makePreview().persistence
    for (index, product) in GenericFoodCatalog.search("ri").prefix(3).enumerated() {
        try? persistence.recordFoodUse(product, grams: 150, at: .now)
        if index == 0 { try? persistence.setFavorite(product, isFavorite: true) }
    }
    return ManualTrackingView(
        viewModel: ManualTrackingViewModel(
            mode: .search,
            lookup: MockFoodLookupService(),
            permissions: MockCameraPermissionService(),
            persistence: persistence
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
