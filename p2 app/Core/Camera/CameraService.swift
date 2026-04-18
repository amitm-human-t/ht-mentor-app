@preconcurrency import AVFoundation
import Foundation
import UIKit
import OSLog

/// Owns the live rear-camera capture session and publishes frames into the
/// shared frame bus used by the inference workers.
@MainActor
@Observable
final class CameraService: NSObject {
    enum SessionState: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var sessionState: SessionState = .idle

    nonisolated(unsafe) let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "p2.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "p2.camera.output", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sampleBufferDelegate = SampleBufferDelegate()
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var frameBus: CameraFrameBus?
    private var configurationTask: Task<Void, Error>?
    @ObservationIgnored private var orientationObserver: AnyObject?

    func refreshAuthorizationStatus() async {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccessIfNeeded() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
            return authorizationStatus
        }
        authorizationStatus = status
        return status
    }

    func startSession(frameBus: CameraFrameBus) async throws {
        let status = await requestAccessIfNeeded()
        guard status == .authorized else {
            AppLogger.runtime.error("Camera start failed because permission was denied")
            sessionState = .failed(CameraError.permissionDenied.localizedDescription)
            throw CameraError.permissionDenied
        }
        self.frameBus = frameBus
        sampleBufferDelegate.frameBus = frameBus
        guard sessionState != .running, sessionState != .starting else { return }
        sessionState = .starting
        do {
            try await configureIfNeeded()
        } catch {
            sessionState = .failed(error.localizedDescription)
            throw error
        }
        AppLogger.runtime.info("Starting live camera session")
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
        sessionState = .running
        registerOrientationObserverIfNeeded()
        applyCurrentOrientation()
    }

    // MARK: - Orientation tracking

    private func registerOrientationObserverIfNeeded() {
        guard orientationObserver == nil else { return }
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyCurrentOrientation()
            }
        }
    }

    func applyCurrentOrientation() {
        let orientation: UIInterfaceOrientation
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            orientation = scene.effectiveGeometry.interfaceOrientation
        } else {
            orientation = .landscapeRight
        }

        let angle: CGFloat = orientation == .landscapeLeft ? 180 : 0
        sampleBufferDelegate.exifOrientation = orientation == .landscapeLeft ? .up : .downMirrored
        AppLogger.runtime.debug("Camera orientation updated — angle=\(Int(angle)) exif=\(orientation == .landscapeLeft ? "up" : "downMirrored", privacy: .public)")

        let capturedOutput = videoOutput
        sessionQueue.async {
            if let connection = capturedOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func stopSession() {
        guard sessionState != .idle else { return }
        AppLogger.runtime.info("Stopping live camera session")
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        sessionState = .idle
    }

    private func configureIfNeeded() async throws {
        guard !configured else { return }
        if let configurationTask {
            try await configurationTask.value
            return
        }

        let session = self.session
        let videoOutput = self.videoOutput
        let outputQueue = self.outputQueue
        let sampleBufferDelegate = self.sampleBufferDelegate

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                sessionQueue.async {
                    do {
                        session.beginConfiguration()
                        session.sessionPreset = .high

                        guard let camera = CameraService.preferredBackCamera() else {
                            AppLogger.runtime.error("No supported rear camera was available")
                            throw CameraError.unavailable
                        }

                        let input = try AVCaptureDeviceInput(device: camera)
                        if session.inputs.isEmpty, session.canAddInput(input) {
                            session.addInput(input)
                        }

                        videoOutput.alwaysDiscardsLateVideoFrames = true
                        videoOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                        ]
                        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: outputQueue)
                        if session.outputs.isEmpty, session.canAddOutput(videoOutput) {
                            session.addOutput(videoOutput)
                            // App is landscape-only. Set rotation angle on the output connection
                            // so pixel buffers are delivered in landscape-right orientation.
                            // Reference: videoRotationAngle=0 for landscapeRight (mentor tests app).
                            if let connection = videoOutput.connection(with: .video),
                               connection.isVideoRotationAngleSupported(0) {
                                connection.videoRotationAngle = 0
                            }
                        }

                        session.commitConfiguration()
                        AppLogger.runtime.info("Configured camera session with device \(camera.localizedName, privacy: .public)")
                        continuation.resume()
                    } catch {
                        session.commitConfiguration()
                        AppLogger.runtime.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        configurationTask = task
        do {
            try await task.value
            configured = true
            configurationTask = nil
        } catch {
            configurationTask = nil
            throw error
        }
    }

    nonisolated private static func preferredBackCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
    }
}

private final class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated(unsafe) var frameBus: CameraFrameBus?
    /// Updated by CameraService.applyCurrentOrientation() when device rotates.
    nonisolated(unsafe) var exifOrientation: CGImagePropertyOrientation = .downMirrored

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let frameBus
        else {
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let orientation = exifOrientation
        Task {
            await frameBus.publish(pixelBuffer: pixelBuffer, timestamp: timestamp, exifOrientation: orientation)
        }
    }
}

enum CameraError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission has not been granted."
        case .unavailable:
            return "Rear camera is unavailable on this device."
        }
    }
}
