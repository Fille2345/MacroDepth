// Services/Health/HealthKitStore.swift

import Foundation
import HealthKit

/// Apple Health through HealthKit.
///
/// Each meal is a food correlation of its energy and macro samples. Every object
/// carries the meal's id twice: as our own metadata key, which queries and deletes
/// match on, and as HealthKit's sync identifier with a rising version, so saving a
/// meal again replaces it instead of adding a duplicate.
final class HealthKitStore: HealthStoreProtocol, @unchecked Sendable {
    static let mealIDKey = "MacroDepthMealID"
    static let fingerprintKey = "MacroDepthFingerprint"

    private struct Nutrient {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let value: @Sendable (HealthMealRecord) -> Double
        /// Energy is always written; a zero macro is left out.
        let writesZero: Bool

        var type: HKQuantityType { HKQuantityType(identifier) }
    }

    private static let nutrients: [Nutrient] = [
        Nutrient(identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), value: { $0.macros.energyKilocalories }, writesZero: true),
        Nutrient(identifier: .dietaryProtein, unit: .gram(), value: { $0.macros.proteinGrams }, writesZero: false),
        Nutrient(identifier: .dietaryCarbohydrates, unit: .gram(), value: { $0.totalCarbohydrateGrams }, writesZero: false),
        Nutrient(identifier: .dietaryFatTotal, unit: .gram(), value: { $0.macros.fatGrams }, writesZero: false),
        Nutrient(identifier: .dietaryFiber, unit: .gram(), value: { $0.macros.fiberGrams }, writesZero: false),
    ]

    private static let foodType = HKCorrelationType(.food)
    private static let bodyMassType = HKQuantityType(.bodyMass)

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        do {
            try await store.requestAuthorization(
                toShare: Set(Self.nutrients.map(\.type)),
                read: [Self.bodyMassType]
            )
        } catch {
            throw HealthSyncError.authorizationFailed(error.localizedDescription)
        }
    }

    func dailyBodyMass(in interval: DateInterval, calendar: Calendar) async throws -> [DailyWeight] {
        let start = calendar.startOfDay(for: interval.start)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: Self.bodyMassType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: interval.end)
            ),
            options: .mostRecent,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await query.result(for: store)
            var weights: [DailyWeight] = []
            collection.enumerateStatistics(from: start, to: interval.end) { statistics, _ in
                guard let quantity = statistics.mostRecentQuantity() else { return }
                weights.append(DailyWeight(
                    day: calendar.startOfDay(for: statistics.startDate),
                    kilograms: quantity.doubleValue(for: .gramUnit(with: .kilo))
                ))
            }
            return weights
        } catch {
            throw Self.map(error)
        }
    }

    func mealFingerprints(in interval: DateInterval) async throws -> [UUID: String] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: interval.start, end: interval.end),
            HKQuery.predicateForObjects(from: .default()),
            HKQuery.predicateForObjects(withMetadataKey: Self.mealIDKey),
        ])
        let query = HKSampleQueryDescriptor(
            predicates: [.correlation(type: Self.foodType, predicate: predicate)],
            sortDescriptors: []
        )
        do {
            return try await query.result(for: store).reduce(into: [:]) { result, correlation in
                guard let idText = correlation.metadata?[Self.mealIDKey] as? String,
                      let id = UUID(uuidString: idText) else { return }
                result[id] = correlation.metadata?[Self.fingerprintKey] as? String ?? ""
            }
        } catch {
            throw Self.map(error)
        }
    }

    func saveMeals(_ meals: [HealthMealRecord]) async throws {
        guard !meals.isEmpty else { return }
        // Must rise with every save for HealthKit to replace the earlier version.
        let version = Int(Date.now.timeIntervalSince1970 * 1_000)
        let correlations = meals.map { Self.correlation(for: $0, version: version) }
        do {
            try await store.save(correlations)
        } catch {
            throw Self.map(error)
        }
    }

    func deleteMeals(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: .default()),
            HKQuery.predicateForObjects(withMetadataKey: Self.mealIDKey, allowedValues: ids.map(\.uuidString)),
        ])
        // The correlation and its samples are deleted separately, so nothing is left behind.
        let types: [HKObjectType] = [Self.foodType] + Self.nutrients.map(\.type)
        for type in types {
            do {
                _ = try await store.deleteObjects(of: type, predicate: predicate)
            } catch let error as HKError where error.code == .errorNoData {
                continue
            } catch {
                throw Self.map(error)
            }
        }
    }

    // MARK: Private

    private static func correlation(for meal: HealthMealRecord, version: Int) -> HKCorrelation {
        let id = meal.id.uuidString
        func metadata(syncSuffix: String) -> [String: Any] {
            [
                mealIDKey: id,
                HKMetadataKeySyncIdentifier: id + syncSuffix,
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyFoodType: meal.mealType.displayName,
            ]
        }

        let samples = nutrients.compactMap { nutrient -> HKQuantitySample? in
            let value = max(nutrient.value(meal), 0)
            guard value > 0 || nutrient.writesZero else { return nil }
            return HKQuantitySample(
                type: nutrient.type,
                quantity: HKQuantity(unit: nutrient.unit, doubleValue: value),
                start: meal.timestamp,
                end: meal.timestamp,
                metadata: metadata(syncSuffix: "." + nutrient.identifier.rawValue)
            )
        }

        var correlationMetadata = metadata(syncSuffix: "")
        correlationMetadata[fingerprintKey] = meal.fingerprint
        return HKCorrelation(
            type: foodType,
            start: meal.timestamp,
            end: meal.timestamp,
            objects: Set(samples),
            metadata: correlationMetadata
        )
    }

    private static func map(_ error: any Error) -> HealthSyncError {
        if let error = error as? HKError {
            switch error.code {
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: return .writeDenied
            case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .unavailable
            default: break
            }
        }
        return .failed(error.localizedDescription)
    }
}
