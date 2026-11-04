// Features/Scan/DetectionOverlayView.swift

import SwiftUI

/// Draws detection boxes over an image. Apply it as an overlay on an image
/// that already has `.aspectRatio(contentMode: .fit)`, so the overlay's frame
/// equals the displayed image rect and normalized boxes map directly onto it.
struct DetectionOverlayView: View {
    let detections: [DetectedFoodItem]

    var body: some View {
        GeometryReader { proxy in
            ForEach(detections) { detection in
                let rect = detection.boundingBox.rect(in: proxy.size)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .topLeading) {
                        Text(detection.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: Capsule())
                            .fixedSize()
                            .offset(x: 4, y: 4)
                    }
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
