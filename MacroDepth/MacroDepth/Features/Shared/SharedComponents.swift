// Features/Shared/SharedComponents.swift

import SwiftUI

/// Energy and the three main macros as a row of tiles.
struct MacroSummaryView: View {
    let macros: MacroNutrients

    var body: some View {
        HStack(spacing: 8) {
            MacroTile(title: "Energy", value: NutritionFormat.kilocalories(macros.energyKilocalories), tint: .orange)
            MacroTile(title: "Protein", value: NutritionFormat.grams(macros.proteinGrams), tint: .red)
            MacroTile(title: "Carbs", value: NutritionFormat.grams(macros.carbohydrateGrams), tint: .blue)
            MacroTile(title: "Fat", value: NutritionFormat.grams(macros.fatGrams), tint: .yellow)
        }
    }
}

private struct MacroTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct ErrorCard: View {
    let presentation: ErrorPresentation
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(presentation.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            switch presentation.action {
            case .retry:
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            case .openSettings:
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProgressRow: View {
    let title: String
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline)
            Spacer()
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Shared components") {
    VStack(spacing: 16) {
        MacroSummaryView(macros: MacroNutrients(proteinGrams: 48, carbohydrateGrams: 54, fatGrams: 6, fiberGrams: 3.6))
        ProgressRow(title: "Identifying food…", onCancel: {})
        ErrorCard(
            presentation: ErrorPresentation(NutritionServiceError.offline),
            onRetry: {},
            onOpenSettings: {}
        )
    }
    .padding()
}
