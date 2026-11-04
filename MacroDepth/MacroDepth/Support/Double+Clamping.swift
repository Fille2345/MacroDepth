// Support/Double+Clamping.swift

import Foundation

extension Double {
    /// Clamped to [0, 1]; non-finite values become 0.
    var clampedToUnitInterval: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}
