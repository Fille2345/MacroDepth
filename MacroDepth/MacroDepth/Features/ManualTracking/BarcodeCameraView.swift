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
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // UPC-A is reported as EAN-13 with a leading zero.
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter(output.availableMetadataObjectTypes.contains)
        return !output.metadataObjectTypes.isEmpty
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let code = metadataObjects
            .compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            .first
        guard let code else { return }
        // The delegate queue is `.main`.
        MainActor.assumeIsolated {
            guard isScanning else { return }
            onDetect(code)
        }
    }
}
