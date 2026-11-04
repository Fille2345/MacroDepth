// Features/Dashboard/DashboardView.swift

import SwiftUI

struct DashboardView: View {
    let viewModel: DashboardViewModel
    let onQuickLog: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var goalEditor: OnboardingViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.errorPresentation {
                        ErrorCard(
                            presentation: error,
                            onRetry: { viewModel.load() },
                            onOpenSettings: {}
                        )
                    }

                    if let progress = viewModel.progress {
                        CalorieGaugeCard(progress: progress)
                        MacroProgressCard(progress: progress)
                    } else if viewModel.errorPresentation == nil {
                        setGoalsCard
                    }

                    quickLogButton
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Goals", systemImage: "slider.horizontal.3") {
                        goalEditor = viewModel.makeGoalEditor()
                    }
                }
            }
        }
        .sheet(item: $goalEditor) { editor in
            OnboardingView(viewModel: editor, onFinished: { goalEditor = nil }, onCancel: { goalEditor = nil })
        }
        .task {
            await viewModel.observeChanges()
        }
        // "Today" changes at midnight and while the app is in the background.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            viewModel.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.load() }
        }
    }

    private var navigationTitle: String {
        viewModel.profile.map { "Today · \($0.goal.shortName)" } ?? "Today"
    }

    private var setGoalsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.largeTitle)
                .foregroundStyle(Color.brandGreen)
            Text("Set your daily targets")
                .font(.headline)
            Text("Add your goal and stats to see calories and macros here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set Up Goals") {
                goalEditor = viewModel.makeGoalEditor()
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var quickLogButton: some View {
        Button(action: onQuickLog) {
            Label("Log a Meal", systemImage: "camera.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandGreen)
    }
}

// MARK: - Calorie gauge

private struct CalorieGaugeCard: View {
    let progress: DailyProgress

    var body: some View {
        VStack(spacing: 20) {
            CalorieRing(progress: progress)
                .frame(width: 200, height: 200)

            HStack {
                sublabel(title: "Eaten", value: progress.eaten.energyKilocalories)
                Divider()
                    .frame(height: 32)
                    .overlay(.white.opacity(0.4))
                sublabel(title: "Target", value: progress.targets.calories)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .foregroundStyle(.white)
        .background(
            // Dark enough for white text in both light and dark mode.
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.45, blue: 0.32), Color(red: 0.03, green: 0.34, blue: 0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func sublabel(title: LocalizedStringKey, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(NutritionFormat.kilocalories(value))
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct CalorieRing: View {
    let progress: DailyProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress.calorieFraction)
                .stroke(
                    progress.isOverTarget ? Color.orange : Color.white,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress.calorieFraction)

            VStack(spacing: 2) {
                Text(abs(progress.remainingCalories), format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(progress.isOverTarget ? "kcal over" : "kcal left")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.9)
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        let amount = NutritionFormat.kilocalories(abs(progress.remainingCalories))
        return progress.isOverTarget ? Text("\(amount) over target") : Text("\(amount) remaining")
    }
}

// MARK: - Macro bars

private struct MacroProgressCard: View {
    let progress: DailyProgress

    var body: some View {
        VStack(spacing: 16) {
            MacroBar(title: "Protein", current: progress.eaten.proteinGrams, target: progress.targets.proteinGrams, tint: .red, isAccented: true)
            MacroBar(title: "Carbs", current: progress.eaten.carbohydrateGrams, target: progress.targets.carbohydrateGrams, tint: .blue)
            MacroBar(title: "Fat", current: progress.eaten.fatGrams, target: progress.targets.fatGrams, tint: .yellow)
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MacroBar: View {
    let title: LocalizedStringKey
    let current: Double
    let target: Double
    let tint: Color
    var isAccented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(isAccented ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                Spacer()
                Text("\(current, format: .number.precision(.fractionLength(0))) / \(NutritionFormat.grams(target))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * DailyProgress.fraction(current, of: target))
                        .animation(.easeOut(duration: 0.5), value: current)
                }
            }
            .frame(height: isAccented ? 12 : 8)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("With meals") {
    let dependencies = AppDependencies.makePreview()
    return DashboardView(viewModel: DashboardViewModel(persistence: dependencies.persistence), onQuickLog: {})
}

#Preview("No profile") {
    let dependencies = AppDependencies.makePreview(seedSampleMeals: false, seedSampleProfile: false)
    return DashboardView(viewModel: DashboardViewModel(persistence: dependencies.persistence), onQuickLog: {})
}
