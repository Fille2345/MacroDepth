// Features/Recipes/RecipesView.swift

import SwiftUI

struct RecipesView: View {
    @Bindable var viewModel: RecipesViewModel
    let onUseInScan: (RecipeSuggestion) -> Void

    @State private var recipeToDelete: SavedMeal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recipeBookSection

                    Text("Suggested for You")
                        .font(.title3.bold())
                        .padding(.top, 8)

                    Picker("Goal", selection: $viewModel.selectedGoal) {
                        ForEach(FitnessGoal.allCases) { goal in
                            Text(goal.shortName).tag(goal)
                        }
                    }
                    .pickerStyle(.segmented)

                    mealTypeFilter

                    if let error = viewModel.errorPresentation {
                        ErrorCard(presentation: error, onRetry: { viewModel.load() }, onOpenSettings: {})
                    }

                    if let remaining = viewModel.remainingCalories, remaining > 0 {
                        Text("You have \(NutritionFormat.kilocalories(remaining)) left today. Recipes that fit come first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.recipes) { recipe in
                        RecipeCard(
                            recipe: recipe,
                            fitsToday: viewModel.remainingCalories == nil ? nil : viewModel.fitsToday(recipe),
                            onUseInScan: { onUseInScan(recipe) }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Recipes")
        }
        .task {
            await viewModel.observeChanges()
        }
        .onDisappear { viewModel.clearConfirmation() }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: Binding(get: { recipeToDelete != nil }, set: { if !$0 { recipeToDelete = nil } }),
            titleVisibility: .visible,
            presenting: recipeToDelete
        ) { savedMeal in
            Button("Delete \(savedMeal.name)", role: .destructive) {
                Task { await viewModel.delete(savedMeal) }
            }
        } message: { _ in
            Text("Meals you've already logged from it stay in your log.")
        }
    }

    @ViewBuilder
    private var recipeBookSection: some View {
        Text("Your Recipe Book")
            .font(.title3.bold())

        if let confirmation = viewModel.loggedConfirmation {
            Label(confirmation, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if viewModel.savedMeals.isEmpty {
            Label("Tap Save as Recipe on a meal in your Log to keep it here.", systemImage: "bookmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.savedMeals) { savedMeal in
                SavedMealCard(
                    savedMeal: savedMeal,
                    imageURL: viewModel.imageURL(for: savedMeal),
                    onLog: { Task { await viewModel.logToday(savedMeal) } },
                    onDelete: { recipeToDelete = savedMeal }
                )
            }
        }
    }

    private var mealTypeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: viewModel.selectedMealType == nil) {
                    viewModel.selectedMealType = nil
                }
                ForEach(MealType.allCases) { mealType in
                    FilterChip(title: mealType.displayName, isSelected: viewModel.selectedMealType == mealType) {
                        viewModel.selectedMealType = mealType
                    }
                }
            }
        }
    }
}

private struct SavedMealCard: View {
    let savedMeal: SavedMeal
    let imageURL: URL?
    let onLog: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(savedMeal.name)
                        .font(.headline)
                    Text(savedMeal.orderedComponents.map(\.name).formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Delete \(savedMeal.name)", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }

            MacroSummaryView(macros: savedMeal.totalMacros)

            Button(action: onLog) {
                Label("Log This Meal Today", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandGreen)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? AnyShapeStyle(Color.brandGreen.opacity(0.85)) : AnyShapeStyle(.background.secondary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RecipeCard: View {
    let recipe: RecipeSuggestion
    /// `nil` when there's no profile to compare against.
    let fitsToday: Bool?
    let onUseInScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(recipe.mealType.displayName, systemImage: recipe.mealType.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if fitsToday == false {
                    Text("Over today's calories")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(recipe.title)
                .font(.headline)

            HStack(spacing: 12) {
                nutrient(NutritionFormat.kilocalories(recipe.estimatedCalories), label: "Energy")
                nutrient(NutritionFormat.grams(recipe.proteinG), label: "Protein")
                nutrient(NutritionFormat.grams(recipe.carbsG), label: "Carbs")
                nutrient(NutritionFormat.grams(recipe.fatG), label: "Fat")
            }

            DisclosureGroup("Ingredients & preparation") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recipe.ingredientsList, id: \.self) { ingredient in
                            Text("• \(ingredient)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(recipe.preparationInstructions.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                        }
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .font(.subheadline)
            .tint(.brandGreen)

            Button(action: onUseInScan) {
                Label("Log / Scan with this recipe", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.brandGreen)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func nutrient(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let dependencies = AppDependencies.makePreview()
    return RecipesView(viewModel: RecipesViewModel(persistence: dependencies.persistence), onUseInScan: { _ in })
}
