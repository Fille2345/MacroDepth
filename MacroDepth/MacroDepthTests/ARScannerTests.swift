// MacroDepthTests/ARScannerTests.swift

import ARKit
import CoreVideo
import Foundation
import ImageIO
import Testing
@testable import MacroDepth

// MARK: - Helpers

private func makeBuffer<Pixel>(width: Int, height: Int, format: OSType, pixels: [Pixel]) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &buffer)
    #expect(status == kCVReturnSuccess)
    let result = try #require(buffer)

    CVPixelBufferLockBaseAddress(result, [])
    defer { CVPixelBufferUnlockBaseAddress(result, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(result))
    let bytesPerRow = CVPixelBufferGetBytesPerRow(result)
    let pixelsPerSource = pixels.count / height
    for row in 0..<height {
        let destination = (base + row * bytesPerRow).assumingMemoryBound(to: Pixel.self)
        for column in 0..<pixelsPerSource {
            destination[column] = pixels[row * pixelsPerSource + column]
        }
    }
    return result
}

/// BGRA image with `isRed` choosing red or blue per pixel.
private func makeImageBuffer(width: Int, height: Int, isRed: (_ column: Int, _ row: Int) -> Bool) throws -> CVPixelBuffer {
    var pixels: [UInt8] = []
    for row in 0..<height {
        for column in 0..<width {
            pixels += isRed(column, row) ? [0, 0, 255, 255] : [255, 0, 0, 255]
        }
    }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    let result = try #require(buffer)
    CVPixelBufferLockBaseAddress(result, [])
    defer { CVPixelBufferUnlockBaseAddress(result, []) }
    let base = try #require(CVPixelBufferGetBaseAddress(result))
    let bytesPerRow = CVPixelBufferGetBytesPerRow(result)
    for row in 0..<height {
        pixels.withUnsafeBytes { source in
            (base + row * bytesPerRow).copyMemory(
                from: source.baseAddress! + row * width * 4,
                byteCount: width * 4
            )
        }
    }
    return result
}

/// Decodes a JPEG and reports whether the pixel at a normalized position is mostly red.
private func isRed(jpeg: Data, x: Double, y: Double) throws -> Bool {
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let column = Int(x * Double(image.width))
    let row = Int(y * Double(image.height))
    let index = (row * image.width + column) * 4
    return pixels[index] > pixels[index + 2]
}

private func jpegSize(_ jpeg: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

// MARK: - Frame conversion

struct ARFrameConverterTests {
    //  1 2 3          4 1
    //  4 5 6    →     5 2
    //                 6 3
    @Test func depthAndConfidenceRotateClockwiseTogether() throws {
        let depth = try makeBuffer(width: 3, height: 2, format: kCVPixelFormatType_DepthFloat32, pixels: [Float32(1), 2, 3, 4, 5, 6])
        let confidence = try makeBuffer(width: 3, height: 2, format: kCVPixelFormatType_OneComponent8, pixels: [UInt8(0), 1, 2, 2, 1, 0])

        let map = try #require(ARFrameConverter.makeUprightDepthMap(depth: depth, confidence: confidence))

        #expect(map.width == 2)
        #expect(map.height == 3)
        #expect(map.depthMeters == [4, 1, 5, 2, 6, 3])
        #expect(map.confidence == [2, 0, 1, 1, 0, 2])
    }

    @Test func depthWithoutConfidenceIsAllowed() throws {
        let depth = try makeBuffer(width: 2, height: 1, format: kCVPixelFormatType_DepthFloat32, pixels: [Float32(1), 2])
        let map = try #require(ARFrameConverter.makeUprightDepthMap(depth: depth, confidence: nil))
        #expect(map.confidence == nil)
    }

    @Test func rejectsWrongDepthFormatAndMismatchedConfidence() throws {
        let wrongFormat = try makeBuffer(width: 2, height: 1, format: kCVPixelFormatType_OneComponent8, pixels: [UInt8(1), 2])
        #expect(ARFrameConverter.makeUprightDepthMap(depth: wrongFormat, confidence: nil) == nil)

        let depth = try makeBuffer(width: 2, height: 1, format: kCVPixelFormatType_DepthFloat32, pixels: [Float32(1), 2])
        let smallConfidence = try makeBuffer(width: 1, height: 1, format: kCVPixelFormatType_OneComponent8, pixels: [UInt8(1)])
        #expect(ARFrameConverter.makeUprightDepthMap(depth: depth, confidence: smallConfidence) == nil)
    }

    /// Red in the sensor's top-left corner must end up top-right when upright.
    @Test func imageIsRotatedUpright() throws {
        let buffer = try makeImageBuffer(width: 80, height: 40) { column, row in column < 40 && row < 20 }

        let (jpeg, pixelSize) = try ARFrameConverter.encodeUprightJPEG(buffer)

        #expect(pixelSize == CGSize(width: 40, height: 80))
        #expect(try jpegSize(jpeg).width == 40)
        #expect(try jpegSize(jpeg).height == 80)
        #expect(try isRed(jpeg: jpeg, x: 0.75, y: 0.25))
        #expect(try !isRed(jpeg: jpeg, x: 0.25, y: 0.25))
        #expect(try !isRed(jpeg: jpeg, x: 0.75, y: 0.75))
    }

    @Test func imageAndDepthStayAligned() throws {
        // The same corner is marked in the image and in the depth map.
        let image = try makeImageBuffer(width: 80, height: 60) { column, row in column < 40 && row < 30 }
        let depth = try makeBuffer(width: 4, height: 3, format: kCVPixelFormatType_DepthFloat32, pixels: [
            Float32(1), 1, 9, 9,
            1, 1, 9, 9,
            9, 9, 9, 9,
        ])

        let (jpeg, _) = try ARFrameConverter.encodeUprightJPEG(image)
        let map = try #require(ARFrameConverter.makeUprightDepthMap(depth: depth, confidence: nil))

        // Normalized (0.75, 0.15) lies inside the marked corner in both, after rotation.
        #expect(try isRed(jpeg: jpeg, x: 0.75, y: 0.15))
        #expect(map.depth(column: Int(0.75 * Double(map.width)), row: Int(0.15 * Double(map.height))) == 1)
        // Normalized (0.25, 0.85) lies outside it in both.
        #expect(try !isRed(jpeg: jpeg, x: 0.25, y: 0.85))
        #expect(map.depth(column: Int(0.25 * Double(map.width)), row: Int(0.85 * Double(map.height))) == 9)
    }

    @Test func largeImagesAreDownscaledForUpload() throws {
        let buffer = try makeImageBuffer(width: 1920, height: 1440) { _, _ in true }
        let (jpeg, pixelSize) = try ARFrameConverter.encodeUprightJPEG(buffer)

        #expect(pixelSize == CGSize(width: 1152, height: 1536))
        #expect(try jpegSize(jpeg).width == 1152)
        #expect(try jpegSize(jpeg).height == 1536)
    }

    @Test func captureCombinesAllFrameData() throws {
        let intrinsics = CameraIntrinsics(focalLengthX: 1000, focalLengthY: 1010, principalPointX: 40, principalPointY: 20, referenceResolution: CGSize(width: 80, height: 40))
        let snapshot = ARFrameSnapshot(
            image: try makeImageBuffer(width: 80, height: 40) { _, _ in true },
            depth: try makeBuffer(width: 2, height: 1, format: kCVPixelFormatType_DepthFloat32, pixels: [Float32(1), 2]),
            confidence: nil,
            intrinsics: intrinsics.matrix,
            cameraTransform: matrix_identity_float4x4
        )

        let capture = try ARFrameConverter.makeCapture(from: snapshot)

        #expect(capture.imagePixelSize == CGSize(width: 40, height: 80))
        #expect(capture.depthMap?.width == 1)
        #expect(capture.depthMap?.height == 2)
        #expect(capture.intrinsics == intrinsics.rotatedClockwise())
        #expect(capture.secondaryImageJPEGData == nil)
    }

    /// Non-LiDAR devices: a frame without depth still produces a usable capture.
    @Test func captureWithoutDepthHasNoDepthMap() throws {
        let snapshot = ARFrameSnapshot(
            image: try makeImageBuffer(width: 80, height: 40) { _, _ in true },
            depth: nil,
            confidence: nil,
            intrinsics: matrix_identity_float3x3,
            cameraTransform: matrix_identity_float4x4
        )
        let capture = try ARFrameConverter.makeCapture(from: snapshot)
        #expect(!capture.hasDepth)
        #expect(!capture.imageJPEGData.isEmpty)
    }
}

// MARK: - Rotation geometry

struct UprightGeometryTests {
    private let sensor = CameraIntrinsics(
        focalLengthX: 1400,
        focalLengthY: 1420,
        principalPointX: 955,
        principalPointY: 725,
        referenceResolution: CGSize(width: 1920, height: 1440)
    )

    private func project(_ point: SIMD3<Float>, _ intrinsics: CameraIntrinsics) -> SIMD2<Float> {
        SIMD2(
            intrinsics.focalLengthX * point.x / point.z + intrinsics.principalPointX,
            intrinsics.focalLengthY * point.y / point.z + intrinsics.principalPointY
        )
    }

    @Test func intrinsicsFollowThePixelRotation() {
        let upright = sensor.rotatedClockwise()
        #expect(upright.referenceResolution == CGSize(width: 1440, height: 1920))

        // A sensor pixel (u, v) moves to (height − v, u).
        let point = SIMD3<Float>(0.08, -0.05, 0.4)
        let original = project(point, sensor)
        let rotatedPoint = SIMD3<Float>(-point.y, point.x, point.z)
        let rotated = project(rotatedPoint, upright)

        #expect(abs(rotated.x - (1440 - original.y)) < 0.01)
        #expect(abs(rotated.y - original.x) < 0.01)
    }

    /// Back-projecting a pixel must give the same world point before and after rotation.
    @Test func poseAndIntrinsicsAgreeOnWorldPoints() {
        let translation = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0.2, 1.1, -0.3, 1)
        ))
        let tilt = simd_float4x4(simd_quatf(angle: 0.6, axis: simd_normalize(SIMD3<Float>(1, 0.4, 0))))
        let sensorPose = CameraPose(matrix: translation * tilt)
        let uprightPose = sensorPose.rotatedClockwise()
        let upright = sensor.rotatedClockwise()

        func worldPoint(_ pose: CameraPose, _ intrinsics: CameraIntrinsics, column: Float, row: Float) -> SIMD3<Float> {
            // `unproject` is x right, y down, z forward; ARKit is x right, y up, z backward.
            let p = intrinsics.unproject(column: column, row: row, depth: 0.45)
            let world = pose.matrix * SIMD4(p.x, -p.y, -p.z, 1)
            return SIMD3(world.x, world.y, world.z)
        }

        let (u, v): (Float, Float) = (300, 1100)
        let before = worldPoint(sensorPose, sensor, column: u, row: v)
        let after = worldPoint(uprightPose, upright, column: 1440 - v, row: u)
        #expect(simd_distance(before, after) < 0.0001)
    }

    @Test func rotationKeepsCameraPosition() {
        let translation = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(1, 2, 3, 1)
        ))
        #expect(CameraPose(matrix: translation).rotatedClockwise().translation == SIMD3<Float>(1, 2, 3))
    }
}

// MARK: - ARKit mapping and service behaviour

@MainActor
struct ARScannerServiceTests {
    @Test func mapsTrackingStates() {
        #expect(ScannerState.TrackingQuality(.normal) == .normal)
        #expect(ScannerState.TrackingQuality(.notAvailable) == .notAvailable)
        guard case .limited(let reason) = ScannerState.TrackingQuality(.limited(.excessiveMotion)) else {
            Issue.record("Expected limited tracking")
            return
        }
        #expect(reason == "Move the phone more slowly")
    }

    @Test func mapsSessionErrors() {
        #expect(ScannerError(sessionError: ARError(.cameraUnauthorized)) == .cameraPermissionDenied)
        #expect(ScannerError(sessionError: ARError(.unsupportedConfiguration)) == .worldTrackingUnsupported)
        guard case .sessionFailed = ScannerError(sessionError: ARError(.sensorFailed)) else {
            Issue.record("Expected sessionFailed")
            return
        }
    }

    @Test func onlyLiDARRequestsSmoothedDepth() {
        #expect(ARScannerService.makeConfiguration(for: .lidar).frameSemantics.contains(.smoothedSceneDepth))
        #expect(ARScannerService.makeConfiguration(for: .cameraOnly).frameSemantics.isEmpty)
    }

    @Test func unsupportedDeviceFailsToStartAndReportsIt() async throws {
        let scanner = ARScannerService(capabilities: .unsupported)
        await #expect(throws: ScannerError.worldTrackingUnsupported) {
            try await scanner.start()
        }
        var iterator = scanner.stateUpdates().makeAsyncIterator()
        #expect(await iterator.next() == .failed(.worldTrackingUnsupported))
    }

    @Test func capturesRequireARunningSession() async {
        let scanner = ARScannerService(capabilities: .cameraOnly)
        await #expect(throws: ScannerError.sessionNotRunning) {
            _ = try await scanner.capture()
        }
        await #expect(throws: ScannerError.sessionNotRunning) {
            _ = try await scanner.captureSecondaryImage()
        }
    }

    @Test func realHardwareGetsTheRealScannerAndSimulatorKeepsTheSimulatedOne() {
        #expect(AppDependencies.makeScanner(for: .lidar) is ARScannerService)
        #expect(AppDependencies.makeScanner(for: .cameraOnly) is ARScannerService)
        #expect(AppDependencies.makeScanner(for: .unsupported) is ARScannerService)
        #expect(AppDependencies.makeScanner(for: .simulated) is SimulatedScannerService)
        #expect(AppDependencies.makeScanner(for: .simulatedWithoutDepth) is SimulatedScannerService)
    }

    @Test func previewSessionIsOnlyAvailableWithTheRealScanner() throws {
        let persistence = try SwiftDataPersistenceService.makeInMemory()
        func viewModel(_ scanner: any ARScannerServiceProtocol) -> ScanViewModel {
            ScanViewModel(
                scanner: scanner,
                nutrition: MockNutritionService(latency: .zero),
                persistence: persistence,
                permissions: MockCameraPermissionService()
            )
        }
        let real = ARScannerService(capabilities: .cameraOnly)
        #expect(viewModel(real).previewSession === real.session)
        #expect(viewModel(SimulatedScannerService()).previewSession == nil)
    }
}

// MARK: - Fallbacks through the whole flow

@MainActor
struct ScannerFallbackTests {
    private func runFlow(capabilities: ScannerCapabilities) async throws -> ScanViewModel {
        let viewModel = ScanViewModel(
            scanner: SimulatedScannerService(capabilities: capabilities, startupDelay: .zero, captureDelay: .zero),
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory(),
            permissions: MockCameraPermissionService()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        func wait(for phase: ScanViewModel.Phase) async throws {
            for _ in 0..<1_000 where viewModel.phase != phase {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(viewModel.phase == phase)
        }

        try await wait(for: .ready)
        viewModel.capturePrimaryPhoto()
        try await wait(for: .awaitingSecondaryPhoto)
        viewModel.captureSecondaryPhoto()
        try await wait(for: .readyToAnalyze)
        viewModel.analyze()
        try await wait(for: .review)
        return viewModel
    }

    @Test func deviceWithoutDepthCompletesWithBothPhotosAndPhotoEstimates() async throws {
        let viewModel = try await runFlow(capabilities: .simulatedWithoutDepth)
        #expect(viewModel.capture?.hasDepth == false)
        #expect(viewModel.capture?.allImagesJPEGData.count == 2)
        #expect(viewModel.hasPhotoOnlyEstimates)
        #expect(!viewModel.drafts.isEmpty)
    }

    @Test func simulatedDepthCompletesWithBothPhotos() async throws {
        let viewModel = try await runFlow(capabilities: .simulated)
        #expect(viewModel.capture?.hasDepth == true)
        #expect(viewModel.capture?.allImagesJPEGData.count == 2)
        #expect(!viewModel.drafts.isEmpty)
    }
}
