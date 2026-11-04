// Services/Scanner/ARFrameConverter.swift

import CoreImage
import CoreVideo
import Foundation
import simd

/// The parts of an `ARFrame` needed for a capture, so the frame itself is released
/// before any `await`. ARKit stops delivering frames if too many are retained.
///
/// `@unchecked Sendable` because `CVPixelBuffer` isn't `Sendable`. These buffers are
/// only ever read, and ARKit doesn't write to a buffer after delivering it.
struct ARFrameSnapshot: @unchecked Sendable {
    let image: CVPixelBuffer
    let depth: CVPixelBuffer?
    let confidence: CVPixelBuffer?
    let intrinsics: simd_float3x3
    let cameraTransform: simd_float4x4
}

/// Turns ARKit's pixel buffers into `Sendable` domain values.
///
/// ARKit delivers images and depth in the sensor's landscape orientation whatever
/// the device orientation. The app is portrait-only, so everything is rotated 90°
/// clockwise *together*: image, depth, confidence, intrinsics and pose. That keeps
/// detection boxes on the image valid for the depth map.
enum ARFrameConverter {
    static let maximumImageDimension: CGFloat = 1536
    static let jpegQuality: CGFloat = 0.8

    /// Creating a `CIContext` is expensive, and a context is safe to share across threads.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// CPU-heavy, so call this off the main actor.
    static func makeCapture(from snapshot: ARFrameSnapshot) throws -> DepthCapture {
        let (jpeg, pixelSize) = try encodeUprightJPEG(snapshot.image)

        var depthMap: DepthMap?
        if let depth = snapshot.depth {
            guard let map = makeUprightDepthMap(depth: depth, confidence: snapshot.confidence) else {
                throw ScannerError.frameUnavailable
            }
            depthMap = map
        }

        let sensorResolution = CGSize(
            width: CVPixelBufferGetWidth(snapshot.image),
            height: CVPixelBufferGetHeight(snapshot.image)
        )
        return DepthCapture(
            imageJPEGData: jpeg,
            imagePixelSize: pixelSize,
            depthMap: depthMap,
            intrinsics: CameraIntrinsics(matrix: snapshot.intrinsics, referenceResolution: sensorResolution).rotatedClockwise(),
            cameraPose: CameraPose(matrix: snapshot.cameraTransform).rotatedClockwise()
        )
    }

    /// Rotates the image upright, downscales it for upload, and encodes it as JPEG.
    static func encodeUprightJPEG(_ buffer: CVPixelBuffer) throws -> (data: Data, pixelSize: CGSize) {
        let upright = CIImage(cvPixelBuffer: buffer).oriented(.right)
        let longestEdge = max(upright.extent.width, upright.extent.height)
        let scale = min(1, maximumImageDimension / longestEdge)
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Scaling can produce a fractional extent, which would add a soft edge row.
        let extent = scaled.extent
        let bounds = CGRect(x: extent.minX, y: extent.minY, width: extent.width.rounded(), height: extent.height.rounded())

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = ciContext.jpegRepresentation(
                  of: scaled.cropped(to: bounds),
                  colorSpace: colorSpace,
                  options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
              ) else {
            throw ScannerError.imageEncodingFailed
        }
        return (data, bounds.size)
    }

    /// Copies a `DepthFloat32` buffer (and optional `OneComponent8` confidence) upright.
    static func makeUprightDepthMap(depth: CVPixelBuffer, confidence: CVPixelBuffer?) -> DepthMap? {
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              let depthValues: [Float] = copyPixels(of: depth) else { return nil }

        var confidenceValues: [UInt8]?
        if let confidence {
            guard CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
                  CVPixelBufferGetWidth(confidence) == CVPixelBufferGetWidth(depth),
                  CVPixelBufferGetHeight(confidence) == CVPixelBufferGetHeight(depth),
                  let values: [UInt8] = copyPixels(of: confidence) else { return nil }
            confidenceValues = values
        }

        return DepthMap(
            width: CVPixelBufferGetWidth(depth),
            height: CVPixelBufferGetHeight(depth),
            depthMeters: depthValues,
            confidence: confidenceValues
        )?.rotatedClockwise()
    }

    /// Row-major copy that honours the buffer's row padding.
    private static func copyPixels<Pixel>(of buffer: CVPixelBuffer) -> [Pixel]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for row in 0..<height {
            let start = (baseAddress + row * bytesPerRow).assumingMemoryBound(to: Pixel.self)
            pixels.append(contentsOf: UnsafeBufferPointer(start: start, count: width))
        }
        return pixels
    }
}
