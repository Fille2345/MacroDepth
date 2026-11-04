// Support/NutritionFormat.swift

import Foundation

/// Locale-aware formatting for nutrition values (metric units).
enum NutritionFormat {
    static func grams(_ value: Double) -> String {
        Measurement(value: value, unit: UnitMass.grams).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    static func kilocalories(_ value: Double) -> String {
        Measurement(value: value, unit: UnitEnergy.kilocalories).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    static func volume(cubicCentimeters value: Double) -> String {
        Measurement(value: value, unit: UnitVolume.cubicCentimeters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    /// For example "248 ± 63 cm³".
    static func volume(_ measurement: VolumeMeasurement) -> String {
        let uncertainty = measurement.uncertaintyCubicCentimeters.formatted(.number.precision(.fractionLength(0)))
        let value = measurement.cubicCentimeters.formatted(.number.precision(.fractionLength(0)))
        return "\(value) ± \(uncertainty) \(UnitVolume.cubicCentimeters.symbol)"
    }

    /// For example "9.8 × 9.8 × 5.0 cm".
    static func dimensions(_ size: FoodVolumeEstimate) -> String {
        let values = [size.widthCentimeters, size.lengthCentimeters, size.heightCentimeters]
            .map { $0.formatted(.number.precision(.fractionLength(1))) }
        return "\(values.joined(separator: " × ")) \(UnitLength.centimeters.symbol)"
    }

    /// For example "0.85 g/cm³".
    static func density(_ gramsPerCubicCentimeter: Double) -> String {
        "\(gramsPerCubicCentimeter.formatted(.number.precision(.fractionLength(2)))) g/\(UnitVolume.cubicCentimeters.symbol)"
    }

    static func centimeters(fromMeters value: Float) -> String {
        Measurement(value: Double(value), unit: UnitLength.meters).converted(to: .centimeters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
