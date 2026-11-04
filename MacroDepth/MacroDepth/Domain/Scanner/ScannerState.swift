// Domain/Scanner/ScannerState.swift

import Foundation

/// Lifecycle of the scanning session, published by `ARScannerServiceProtocol`.
enum ScannerState: Sendable, Equatable {
    enum TrackingQuality: Sendable, Equatable {
        case normal
        case limited(reason: String)
        case notAvailable
    }

    case idle
    case starting
    case running(TrackingQuality)
    case interrupted
    case failed(ScannerError)

    var isReadyToCapture: Bool {
        if case .running(let quality) = self, quality != .notAvailable {
            return true
        }
        return false
    }

    var displayText: String {
        switch self {
        case .idle: "Scanner idle"
        case .starting: "Starting scanner…"
        case .running(.normal): "Point at your plate"
        case .running(.limited(let reason)): reason
        case .running(.notAvailable): "Tracking unavailable — move the phone slowly"
        case .interrupted: "Scanner interrupted"
        case .failed(let error): error.errorDescription ?? "Scanner failed"
        }
    }
}
