// Features/Log/LogView.swift

import SwiftUI

struct LogView: View {
    let viewModel: LogViewModel

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
                            MealRow(meal: meal)
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
