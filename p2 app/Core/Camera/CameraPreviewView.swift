import SwiftUI
import AVFoundation
import AVKit
import OSLog

/// Holds a weak reference to the live PreviewHostView so that SwiftUI overlay
/// views can call `convertYOLORect` without bridging UIKit through bindings.
/// Not Observable — the converter is read at render time by the overlay.
final class PreviewCoordinate {
    weak var hostView: PreviewHostView?

    /// Convert a normalised YOLO rect to SwiftUI view coordinates.
    /// Falls back to the flip-based approximation when the view is unavailable.
    func convert(_ rect: CGRect) -> CGRect {
        if let hostView {
            return hostView.convertYOLORect(rect)
        }
        // Flip-only approximation: correct for landscape when camera fills the view.
        return CGRect(
            x: 1.0 - rect.maxX,
            y: 1.0 - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Shared coordinator — caller owns the instance; we populate `hostView` in makeUIView/updateUIView.
    let coordinate: PreviewCoordinate

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        // App is landscape-only. Ensure the preview connection uses the correct
        // landscape-right rotation so that layerRectConverted returns accurate
        // view-space coordinates for the detection box overlay.
        setLandscapeRotation(on: view.previewLayer)
        coordinate.hostView = view
        AppLogger.runtime.debug("Created camera preview host view")
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer.session = session
        setLandscapeRotation(on: uiView.previewLayer)
        coordinate.hostView = uiView
    }

    private func setLandscapeRotation(on layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection,
              connection.isVideoRotationAngleSupported(0) else { return }
        connection.videoRotationAngle = 0
    }
}

struct DebugVideoPreviewView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        AppLogger.video.debug("Created debug video preview host view")
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PreviewHostView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Convert a normalised YOLO bounding rect (origin top-left, 0…1 in both axes,
    /// using the model's coordinate space where (0,0) is the top-left of the input image
    /// with the device in landscape-right) to a CGRect in this view's coordinate space.
    ///
    /// The Vision metadata coordinate system has (0,0) at bottom-left and x going right,
    /// y going up, so we must flip before calling `layerRectConverted`.
    ///
    /// This is the same pattern validated in the mentor-tests reference app:
    ///   metadataRect.x = 1 - detection.rect.maxX
    ///   metadataRect.y = 1 - detection.rect.minY - detection.rect.height
    func convertYOLORect(_ normalized: CGRect) -> CGRect {
        let metadataRect = CGRect(
            x: 1.0 - normalized.maxX,
            y: 1.0 - normalized.minY - normalized.height,
            width: normalized.width,
            height: normalized.height
        )
        return previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
    }
}

final class PlayerHostView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
