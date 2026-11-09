// Features/Progress/ProgressTrackerView.swift

import Charts
import SwiftUI

extension Color {
    /// Calories on charts. The app's plain orange is too faint as a bar on a light
    /// background and too light on a dark one, by the palette validator's checks.
    static let chartCalories = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.78, green: 0.42, blue: 0.05, alpha: 1)
            : UIColor(red: 0.78, green: 0.37, blue: 0.02, alpha: 1)
    })
}

/// Weight and intake over the same dates. They're separate charts on a shared time
/// axis rather than one chart with two scales, because lining up two scales would
/// suggest a relationship the data may not have.
struct ProgressTrackerView: View {
    @Bindable var viewModel: ProgressTrackerViewModel
    @FocusState private var isEnteringWeight: Bool

    var body: some View {
        List {
            if let error = viewModel.errorPresentation {
                Section {
                    ErrorCard(presentation: error, onRetry: { viewModel.load() }, onOpenSettings: {})
                        .listRowInsets(EdgeInsets())
                }
            }

            logWeightSection

            Section {
                Picker("Time range", selection: $viewModel.selectedRange) {
                    ForEach(ProgressRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                summaryTiles
            }

            Section {
                selectionReadout
                weightChart
                calorieChart
                proteinChart
            }

            if !viewModel.weightEntries.isEmpty {
                Section {
                    ForEach(viewModel.weightEntries) { entry in
                        LabeledContent {
                            HStack(spacing: 6) {
                                if entry.isFromHealth {
                                    Image(systemName: "heart.fill")
                                        .font(.caption)
                                        .foregroundStyle(.pink)
                                        .accessibilityLabel("From Apple Health")
                                }
                                Text(NutritionFormat.weight(kilograms: entry.weightKg))
                            }
                        } label: {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        }
                        .swipeActions {
                            // Health's weigh-ins are deleted in Health, or they'd come back.
                            if !entry.isFromHealth {
                                Button(role: .destructive) {
                                    viewModel.deleteWeight(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Weigh-ins")
                } footer: {
                    if viewModel.weightEntries.contains(where: \.isFromHealth) {
                        Label("From Apple Health. Change or delete these in the Health app.", systemImage: "heart.fill")
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .scrollDismissesKeyboard(.interactively)
        .task {
            await viewModel.observeChanges()
        }
        .alert(
            "Update Your Targets?",
            isPresented: Binding(
                get: { viewModel.targetPrompt != nil },
                set: { if !$0 { viewModel.dismissTargetPrompt() } }
            ),
            presenting: viewModel.targetPrompt
        ) { prompt in
            Button("Update Targets") { viewModel.applyTargetUpdate(prompt) }
            Button("Not Now", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
    }

    // MARK: Logging

    private var logWeightSection: some View {
        Section("Log Weight") {
            DatePicker("Date", selection: $viewModel.weightDate, in: ...viewModel.latestDate, displayedComponents: .date)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Weight", text: $viewModel.weightText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEnteringWeight)
                    Text("kg")
                        .foregroundStyle(.secondary)
                    Button("Log") {
                        isEnteringWeight = false
                        viewModel.logWeight()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandGreen)
                    .disabled(viewModel.parsedWeight == nil)
                }
                if let error = viewModel.weightError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: Summary

    private var summaryTiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SummaryTile(title: "Avg. energy", value: viewModel.averages.map { NutritionFormat.kilocalories($0.calories) })
                SummaryTile(title: "Avg. protein", value: viewModel.averages.map { NutritionFormat.grams($0.proteinGrams) })
                SummaryTile(title: "Weight trend", value: viewModel.weightChange.map(NutritionFormat.weightChange))
            }
            if let averages = viewModel.averages {
                Text("Averages use \(averages.dayCount) finished \(averages.dayCount == 1 ? "day" : "days") with meals logged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Readout

    private var selectionReadout: some View {
        Group {
            if let date = viewModel.selectedChartDate {
                let summary = viewModel.summary(for: date)
                let values = [
                    summary.intake.map { NutritionFormat.kilocalories($0.calories) },
                    summary.intake.map { "\(NutritionFormat.grams($0.proteinGrams)) protein" },
                    summary.weight.map { NutritionFormat.weight(kilograms: $0.kilograms) },
                ].compactMap { $0 }
                Text("\(summary.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(values.isEmpty ? String(localized: "nothing logged") : values.joined(separator: " · "))")
                    .foregroundStyle(.primary)
            } else {
                Text("Touch a chart to see that day's values.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Charts

    private var selectedDay: Date? {
        viewModel.selectedChartDate.map { viewModel.summary(for: $0).day }
    }

    private var weightChart: some View {
        ChartCard(title: "Weight") {
            if viewModel.weightPoints.isEmpty {
                EmptyChartLabel(text: "Log your weight to start your trend.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Chart {
                        ForEach(viewModel.weightPoints) { point in
                            PointMark(x: .value("Date", point.date, unit: .day), y: .value("Weight", point.kilograms))
                                .symbolSize(50)
                                .foregroundStyle(Color.brandGreen.opacity(0.55))
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(NutritionFormat.weight(kilograms: point.kilograms))
                        }
                        if viewModel.showsTrendLine {
                            ForEach(viewModel.weightTrend) { point in
                                LineMark(x: .value("Date", point.date, unit: .day), y: .value("7-day average", point.kilograms))
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(Color.brandGreen)
                                    .accessibilityHidden(true)
                            }
                        }
                        selectionRule
                    }
                    .chartYScale(domain: weightDomain)
                    .progressChartStyle(domain: viewModel.chartDomain, selection: $viewModel.selectedChartDate, range: viewModel.selectedRange)

                    HStack(spacing: 14) {
                        LegendEntry(title: "Weigh-in") {
                            Circle().fill(Color.brandGreen.opacity(0.55)).frame(width: 8, height: 8)
                        }
                        if viewModel.showsTrendLine {
                            LegendEntry(title: "7-day average") {
                                Capsule().fill(Color.brandGreen).frame(width: 16, height: 2)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Weight doesn't start at zero: the changes that matter would be invisible on a scale from 0.
    private var weightDomain: ClosedRange<Double> {
        let values = viewModel.weightPoints.map(\.kilograms) + viewModel.weightTrend.map(\.kilograms)
        let low = (values.min() ?? 70).rounded(.down)
        let high = (values.max() ?? 80).rounded(.up)
        return (low - 1)...(high + 1)
    }

    private var calorieChart: some View {
        intakeChart(
            title: "Calories",
            unitLabel: "kcal",
            value: \.calories,
            target: viewModel.targets?.calories,
            color: .chartCalories,
            format: NutritionFormat.kilocalories
        )
    }

    private var proteinChart: some View {
        intakeChart(
            title: "Protein",
            unitLabel: "g",
            value: \.proteinGrams,
            target: viewModel.targets?.proteinGrams,
            color: .red,
            format: NutritionFormat.grams
        )
    }

    private func intakeChart(
        title: LocalizedStringKey,
        unitLabel: String,
        value: KeyPath<DailyIntake, Double>,
        target: Double?,
        color: Color,
        format: @escaping (Double) -> String
    ) -> some View {
        ChartCard(title: title) {
            if viewModel.intake.isEmpty {
                EmptyChartLabel(text: "Log a meal to see your intake here.")
            } else {
                Chart {
                    ForEach(viewModel.intake) { day in
                        BarMark(
                            x: .value("Date", day.day, unit: .day),
                            y: .value(unitLabel, day[keyPath: value]),
                            width: .ratio(0.6)
                        )
                        .cornerRadius(2)
                        .foregroundStyle(color)
                        .accessibilityLabel(day.day.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(format(day[keyPath: value]))
                    }
                    if let target {
                        RuleMark(y: .value("Target", target))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.secondary)
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text("Target \(format(target))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Target")
                            .accessibilityValue(format(target))
                    }
                    selectionRule
                }
                .chartYScale(domain: 0...(max(target ?? 0, viewModel.intake.map { $0[keyPath: value] }.max() ?? 0) * 1.2))
                .progressChartStyle(domain: viewModel.chartDomain, selection: $viewModel.selectedChartDate, range: viewModel.selectedRange)
            }
        }
    }

    @ChartContentBuilder
    private var selectionRule: some ChartContent {
        if let selectedDay {
            RuleMark(x: .value("Selected", selectedDay, unit: .day))
                .foregroundStyle(Color.secondary.opacity(0.4))
        }
    }
}

// MARK: - Chart parts

private extension View {
    /// The same time axis and label widths on every chart, so their dates line up vertically.
    func progressChartStyle(
        domain: ClosedRange<Date>,
        selection: Binding<Date?>,
        range: ProgressRange
    ) -> some View {
        self
            .chartXScale(domain: domain)
            .chartXSelection(value: selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number, format: .number.precision(.fractionLength(0)))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: 140)
    }
}

private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
        }
        .padding(.vertical, 4)
    }
}

private struct EmptyChartLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct LegendEntry<Swatch: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let swatch: Swatch

    var body: some View {
        HStack(spacing: 5) {
            swatch
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SummaryTile: View {
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

#Preview("With data") {
    let dependencies = AppDependencies.makePreview(seedSampleProgress: true)
    return NavigationStack {
        ProgressTrackerView(viewModel: ProgressTrackerViewModel(persistence: dependencies.persistence))
    }
}

#Preview("Empty") {
    let dependencies = AppDependencies.makePreview(seedSampleMeals: false)
    return NavigationStack {
        ProgressTrackerView(viewModel: ProgressTrackerViewModel(persistence: dependencies.persistence))
    }
}
