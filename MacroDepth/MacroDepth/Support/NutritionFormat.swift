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

    static func centimeters(fromMeters value: Float) -> String {
        Measurement(value: Double(value), unit: UnitLength.meters).converted(to: .centimeters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
