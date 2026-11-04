// Services/Permissions/CameraPermissionService.swift

import AVFoundation
import Foundation

enum CameraPermissionStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    /// The error that blocks scanning, if any.
    var blockingError: ScannerError? {
        switch self {
        case .authorized, .notDetermined: nil
        case .denied: .cameraPermissionDenied
        case .restricted: .cameraPermissionRestricted
        }
    }
}

protocol CameraPermissionProviding: Sendable {
    func currentStatus() -> CameraPermissionStatus
    /// Prompts the user if the status is undetermined; otherwise returns the current status.
    func requestAccess() async -> CameraPermissionStatus
}

struct SystemCameraPermissionService: CameraPermissionProviding {
    func currentStatus() -> CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CameraPermissionStatus {
        let status = currentStatus()
        guard status == .notDetermined else { return status }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

struct MockCameraPermissionService: CameraPermissionProviding {
    let status: CameraPermissionStatus
    let grantsOnRequest: Bool

    init(status: CameraPermissionStatus = .authorized, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    func currentStatus() -> CameraPermissionStatus { status }

    func requestAccess() async -> CameraPermissionStatus {
        guard status == .notDetermined else { return status }
        return grantsOnRequest ? .authorized : .denied
    }
}
