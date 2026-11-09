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
    /// `"health"` when imported from Apple Health; `nil` when entered in the app.
    /// Optional, so existing stores migrate automatically.
    var sourceRawValue: String?

    static let healthSource = "health"

    init(id: UUID = UUID(), date: Date, weightKg: Double, isFromHealth: Bool = false) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.sourceRawValue = isFromHealth ? Self.healthSource : nil
    }

    /// Kept in step with Apple Health while sync is on, so it's changed or deleted there.
    var isFromHealth: Bool { sourceRawValue == Self.healthSource }
}
