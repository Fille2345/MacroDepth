// Domain/Errors/ScannerError.swift

import Foundation

enum ScannerError: Error, Equatable, Sendable, LocalizedError {
    case cameraPermissionDenied
    case cameraPermissionRestricted
    case worldTrackingUnsupported
    case lidarUnavailable
    case sessionNotRunning
    case sessionInterrupted
    case sessionFailed(reason: String)
    case captureTimedOut
    case frameUnavailable
    case imageEncodingFailed

    var isPermissionError: Bool {
        self == .cameraPermissionDenied || self == .cameraPermissionRestricted
    }

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied: "Camera access is turned off for MacroDepth."
        case .cameraPermissionRestricted: "Camera access is restricted on this device."
        case .worldTrackingUnsupported: "This device doesn't support AR tracking."
        case .lidarUnavailable: "This device has no LiDAR depth sensor."
        case .sessionNotRunning: "The scanner isn't running yet."
        case .sessionInterrupted: "The scanner was interrupted."
        case .sessionFailed(let reason): "The scanner stopped: \(reason)"
        case .captureTimedOut: "Capturing a frame took too long."
        case .frameUnavailable: "No camera frame was available to capture."
        case .imageEncodingFailed: "The captured image couldn't be encoded."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cameraPermissionDenied: "Allow camera access in Settings to scan meals."
        case .cameraPermissionRestricted: "Screen Time or a device profile may be blocking the camera."
        case .worldTrackingUnsupported, .lidarUnavailable: "Portions will be estimated from photos instead."
        case .sessionNotRunning, .frameUnavailable, .captureTimedOut: "Hold the phone steady over the plate and try again."
        case .sessionInterrupted: "Return to the app and keep it in the foreground while scanning."
        case .sessionFailed, .imageEncodingFailed: "Try again. Restart the app if it keeps happening."
        }
    }
}
