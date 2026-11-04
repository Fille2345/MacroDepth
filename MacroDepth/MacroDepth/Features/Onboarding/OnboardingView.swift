// Features/Onboarding/OnboardingView.swift

import SwiftUI

/// Goal → stats → review. Used on first launch and from the Dashboard's Edit Goals button.
struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onFinished: () -> Void
    /// `nil` on first launch, when the flow can't be dismissed.
    var onCancel: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(
                    value: Double(viewModel.step.rawValue + 1),
                    total: Double(OnboardingViewModel.Step.allCases.count)
                )
                .tint(.brandGreen)
                .padding(.horizontal)
                .accessibilityLabel("Step \(viewModel.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")

                ScrollView {
                    Group {
                        switch viewModel.step {
                        case .goal: GoalStep(viewModel: viewModel)
                        case .stats: StatsStep(viewModel: viewModel)
                        case .review: ReviewStep(viewModel: viewModel)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)

                navigationButtons
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
        }
        .interactiveDismissDisabled(onCancel == nil)
    }

    private var navigationTitle: LocalizedStringKey {
        switch viewModel.step {
        case .goal: "Your Goal"
        case .stats: "Your Stats"
        case .review: "Your Targets"
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if viewModel.step == .review {
                    if viewModel.save() { onFinished() }
                } else {
                    viewModel.advance()
                }
            } label: {
                Text(viewModel.step == .review ? "Save" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandGreen)
            .disabled(!viewModel.canAdvance)
        }
        .controlSize(.large)
        .padding()
    }
}

// MARK: - Step 1: goal

private struct GoalStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's your primary goal?")
                .font(.title2.bold())
            ForEach(FitnessGoal.allCases) { goal in
                SelectionCard(
                    title: goal.displayName,
                    subtitle: goal.summary,
                    systemImage: goal.systemImage,
                    isSelected: viewModel.goal == goal
                ) {
                    viewModel.goal = goal
                }
            }
        }
    }
}

// MARK: - Step 2: stats

private struct StatsStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberField(title: "Weight", unit: "kg", text: $viewModel.weightText, keyboard: .decimalPad, error: viewModel.weightError)
            NumberField(title: "Height", unit: "cm", text: $viewModel.heightText, keyboard: .decimalPad, error: viewModel.heightError)
            NumberField(title: "Age", unit: "years", text: $viewModel.ageText, keyboard: .numberPad, error: viewModel.ageError)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sex")
                    .font(.subheadline.weight(.medium))
                Picker("Sex", selection: $viewModel.biologicalSex) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.displayName).tag(Optional(sex))
                    }
                }
                .pickerStyle(.segmented)
                Text("The metabolic rate equation is defined using biological sex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Activity level")
                    .font(.subheadline.weight(.medium))
                ForEach(ActivityLevel.allCases) { level in
                    SelectionCard(
                        title: level.displayName,
                        subtitle: level.summary,
                        systemImage: nil,
                        isSelected: viewModel.activityLevel == level
                    ) {
                        viewModel.activityLevel = level
                    }
                }
            }
        }
    }
}

private struct NumberField: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    @Binding var text: String
    let keyboard: UIKeyboardType
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                TextField(title, text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .textFieldStyle(.roundedBorder)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Step 3: review

private struct ReviewStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        if let targets = viewModel.targets, let draft = viewModel.draft {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 4) {
                    Text(targets.calories, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.brandGreen)
                    Text("kcal per day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Protein \(NutritionFormat.grams(targets.proteinGrams))")
                        .font(.headline)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                Text("Estimated BMR \(NutritionFormat.kilocalories(targets.basalMetabolicRate)) · daily burn \(NutritionFormat.kilocalories(targets.totalDailyEnergyExpenditure))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                warnings(targets: targets, draft: draft)

                VStack(spacing: 0) {
                    TargetStepper(
                        title: "Calories",
                        value: NutritionFormat.kilocalories(targets.calories),
                        onIncrement: { viewModel.adjustCalories(by: OnboardingViewModel.calorieStep) },
                        onDecrement: { viewModel.adjustCalories(by: -OnboardingViewModel.calorieStep) }
                    )
                    Divider()
                    TargetStepper(
                        title: "Protein",
                        value: NutritionFormat.grams(targets.proteinGrams),
                        onIncrement: { viewModel.adjustProtein(by: OnboardingViewModel.macroStep) },
                        onDecrement: { viewModel.adjustProtein(by: -OnboardingViewModel.macroStep) }
                    )
                    Divider()
                    TargetStepper(
                        title: "Carbs",
                        value: NutritionFormat.grams(targets.carbohydrateGrams),
                        onIncrement: { viewModel.adjustCarbohydrate(by: OnboardingViewModel.macroStep) },
                        onDecrement: { viewModel.adjustCarbohydrate(by: -OnboardingViewModel.macroStep) }
                    )
                    Divider()
                    TargetStepper(
                        title: "Fat",
                        value: NutritionFormat.grams(targets.fatGrams),
                        onIncrement: { viewModel.adjustFat(by: OnboardingViewModel.macroStep) },
                        onDecrement: { viewModel.adjustFat(by: -OnboardingViewModel.macroStep) }
                    )
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                if viewModel.hasOverrides {
                    Button("Reset to Calculated Targets") {
                        viewModel.resetOverrides()
                    }
                    .frame(maxWidth: .infinity)
                }

                if let error = viewModel.saveError {
                    ErrorCard(presentation: error, onRetry: {}, onOpenSettings: {})
                }

                Text("These are general estimates, not medical advice. Check with a healthcare professional if you're pregnant, have a medical condition, or have a history of disordered eating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func warnings(targets: NutritionTargets, draft: UserProfileDraft) -> some View {
        if draft.isUnderweightForFatLoss {
            WarningLabel("Your BMI is under \(UserProfileDraft.underweightBodyMassIndex.formatted()), so a calorie deficit isn't recommended. Consider Maintain instead.")
        }
        if targets.calorieFloorApplied {
            WarningLabel("Your calculated target was below the minimum for your profile, so it was raised to \(NutritionFormat.kilocalories(targets.calories)).")
        }
        if targets.hasMacroMismatch {
            WarningLabel("Your macros add up to \(NutritionFormat.kilocalories(targets.macroCalories)), which doesn't match your calorie target.")
        }
    }
}

private struct WarningLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}

private struct TargetStepper: View {
    let title: LocalizedStringKey
    let value: String
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        Stepper(onIncrement: onIncrement, onDecrement: onDecrement) {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared

private struct SelectionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.brandGreen)
                        .frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.brandGreen : Color.secondary)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.brandGreen : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    let dependencies = AppDependencies.makePreview(seedSampleProfile: false)
    return OnboardingView(viewModel: OnboardingViewModel(persistence: dependencies.persistence), onFinished: {})
}
