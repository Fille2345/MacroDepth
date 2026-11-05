// Features/ManualTracking/BarcodeCameraView.swift

import AVFoundation
import SwiftUI

/// Live camera that reports retail barcodes. The caller must make sure the AR session
/// has released the camera first, because the two can't run at the same time.
struct BarcodeCameraView: UIViewControllerRepresentable {
    var isScanning: Bool
    let onDetect: (String) -> Void
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        BarcodeCameraController(onDetect: onDetect, onFailure: onFailure)
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {
        controller.onDetect = onDetect
        controller.setScanning(isScanning)
    }
}

final class BarcodeCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    /// `AVCaptureSession` must be started and stopped off the main thread, and it's safe to use there.
    private struct SessionHandle: @unchecked Sendable {
        let session = AVCaptureSession()
    }

    var onDetect: (String) -> Void
    private let onFailure: () -> Void
    private let handle = SessionHandle()
    private let sessionQueue = DispatchQueue(label: "MacroDepth.BarcodeCamera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isScanning = false

    init(onDetect: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
        self.onDetect = onDetect
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard configureSession() else {
            onFailure()
            return
        }
        let layer = AVCaptureVideoPreviewLayer(session: handle.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func setScanning(_ scanning: Bool) {
        guard isScanning != scanning else { return }
        isScanning = scanning
        updateSession()
    }

    private func updateSession() {
        if isScanning { startSession() } else { stopSession() }
    }

    private func startSession() {
        let handle = handle
        sessionQueue.async {
            if !handle.session.isRunning { handle.session.startRunning() }
        }
    }

    private func stopSession() {
        let handle = handle
        sessionQueue.async {
            if handle.session.isRunning { handle.session.stopRunning() }
        }
    }

    private func configureSession() -> Bool {
        let session = handle.session
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        configureFocus(of: device)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // UPC-A is reported as EAN-13 with a leading zero, and UPC-E is expanded on detection.
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter(output.availableMetadataObjectTypes.contains)
        return !output.metadataObjectTypes.isEmpty
    }

    /// Keeps a barcode sharp up close. Failing to set this only makes scanning harder,
    /// so it never stops the camera from starting.
    private func configureFocus(of device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
        } catch {
            return
        }
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.videoZoomFactor = min(
            Self.recommendedZoom(
                minimumFocusDistanceMillimeters: device.minimumFocusDistance,
                fieldOfViewDegrees: device.activeFormat.videoFieldOfView
            ),
            device.activeFormat.videoMaxZoomFactor
        )
    }

    /// The zoom that lets a barcode fill the frame from beyond the closest distance the camera
    /// can focus at. Main cameras on LiDAR iPhones can't focus at around 10 cm, where a barcode
    /// would otherwise fill the frame, so without zoom people hold it too close and it stays
    /// blurry. Based on Apple's approach for scanning codes.
    nonisolated static func recommendedZoom(minimumFocusDistanceMillimeters: Int, fieldOfViewDegrees: Float) -> CGFloat {
        // A typical retail barcode is about 35 mm wide, and should fill 60% of the frame.
        let fillWidthMillimeters = 35.0 / 0.6
        let maximumZoom = 3.0
        guard minimumFocusDistanceMillimeters > 0, fieldOfViewDegrees > 0 else { return 1 }
        let halfAngle = Double(fieldOfViewDegrees) / 2 * .pi / 180
        let distanceThatFills = fillWidthMillimeters / tan(halfAngle)
        return CGFloat(min(max(Double(minimumFocusDistanceMillimeters) / distanceThatFills, 1), maximumZoom))
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let code = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap { object -> String? in
                guard let value = object.stringValue else { return nil }
                return object.type == .upce ? FoodBarcode.upcA(fromUPCE: value) : value
            }
            .first
        guard let code else { return }
        // The delegate queue is `.main`.
        MainActor.assumeIsolated {
            guard isScanning else { return }
            onDetect(code)
        }
    }
}
