// Features/Log/LogView.swift

import SwiftUI

struct LogView: View {
    let viewModel: LogViewModel

    @State private var mealToSave: MealEntry?
    @State private var recipeName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dayNavigator
                    MacroSummaryView(macros: viewModel.dayTotals)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                }

                if let error = viewModel.errorPresentation {
                    Section {
                        ErrorCard(
                            presentation: error,
                            onRetry: { viewModel.load() },
                            onOpenSettings: { viewModel.dismissError() }
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }

                if let confirmation = viewModel.savedConfirmation {
                    Section {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                    }
                }

                if viewModel.meals.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No meals logged",
                            systemImage: "fork.knife",
                            description: Text("Meals you scan will appear here.")
                        )
                    }
                } else {
                    Section("Meals") {
                        ForEach(viewModel.meals) { meal in
                            MealRow(meal: meal) {
                                recipeName = viewModel.suggestedRecipeName(for: meal)
                                mealToSave = meal
                            }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await viewModel.delete(meal) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .toolbar {
                if !viewModel.isShowingToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") { viewModel.goToToday() }
                    }
                }
            }
            .onAppear { viewModel.load() }
            .onDisappear { viewModel.clearConfirmation() }
            .alert(
                "Save as Recipe",
                isPresented: Binding(get: { mealToSave != nil }, set: { if !$0 { mealToSave = nil } }),
                presenting: mealToSave
            ) { meal in
                TextField("Recipe name", text: $recipeName)
                Button("Save") {
                    Task { await viewModel.saveAsRecipe(meal, name: recipeName) }
                }
                .disabled(SavedMeal.validatedName(recipeName) == nil)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Keep this meal in your Recipe Book so you can log it again.")
            }
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button {
                viewModel.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")

            Spacer()
            Text(dayTitle)
                .font(.headline)
            Spacer()

            Button {
                viewModel.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
    }

    private var dayTitle: String {
        viewModel.isShowingToday
            ? String(localized: "Today")
            : viewModel.selectedDay.formatted(.dateTime.weekday(.wide).day().month())
    }
}

private struct MealRow: View {
    let meal: MealEntry
    let onSaveAsRecipe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(meal.mealType.displayName, systemImage: meal.mealType.systemImage)
                    .font(.headline)
                Spacer()
                Text(NutritionFormat.kilocalories(meal.totalMacros.energyKilocalories))
                    .font(.subheadline.monospacedDigit())
            }
            Text(meal.orderedItems.map(\.name).formatted(.list(type: .and)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(meal.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let savedMeal = meal.savedMeal {
                Label("From \(savedMeal.name)", systemImage: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                Button(action: onSaveAsRecipe) {
                    Label("Save as Recipe", systemImage: "bookmark")
                        .foregroundStyle(Color.brandGreen)
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("With meals") {
    let dependencies = AppDependencies.makePreview()
    return LogView(viewModel: LogViewModel(persistence: dependencies.persistence))
}

#Preview("Empty") {
    let dependencies = AppDependencies.makePreview(seedSampleMeals: false)
    return LogView(viewModel: LogViewModel(persistence: dependencies.persistence))
}
