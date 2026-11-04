// Domain/Persistence/WeightEntry.swift

import Foundation
import SwiftData

/// One day's body weight. The service keeps at most one entry per calendar day,
/// so `date` is always the start of that day.
@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double

    init(id: UUID = UUID(), date: Date, weightKg: Double) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
    }
}
