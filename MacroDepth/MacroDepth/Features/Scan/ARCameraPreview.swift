// Features/Scan/ARCameraPreview.swift

import ARKit
import RealityKit
import SwiftUI

/// Live camera feed from the scanner's `ARSession`. The session is owned and run by
/// `ARScannerService`; this view only displays it.
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> UIView {
        #if targetEnvironment(simulator)
        // The Simulator has no camera, and always uses `SimulatedScannerService`.
        return UIView()
        #else
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        // Only the camera feed is shown, so turn off effects meant for rendered content.
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableGroundingShadows, .disableAREnvironmentLighting]
        return view
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
