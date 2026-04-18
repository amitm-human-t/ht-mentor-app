import SwiftUI
import AVFoundation
import AVKit
import OSLog

/// Holds a weak reference to the live PreviewHostView so that SwiftUI overlay
/// views can call `convertYOLORect` without bridging UIKit through bindings.
/// Not Observable — the converter is read at render time by the overlay.
final class PreviewCoordinate {
    weak var hostView: PreviewHostView?
    /// Set from AppPreviewStageView via onGeometryChange so the debug-video
    /// fallback path can scale normalised rects to view pixels.
    var viewSize: CGSize = .zero

    /// Convert a normalised YOLO rect to SwiftUI view coordinates.
    /// Live camera path: uses layerRectConverted for accurate pixel coords.
    /// Debug video path: flips then scales to view size.
    func convert(_ rect: CGRect) -> CGRect {
        if let hostView {
            return hostView.convertYOLORect(rect)
        }
        // Flip to match Vision output space, then scale to view pixels.
        let flipped = CGRect(
            x: 1.0 - rect.maxX,
            y: 1.0 - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
        guard viewSize.width > 0 && viewSize.height > 0 else { return flipped }
        return CGRect(
            x: flipped.origin.x * viewSize.width,
            y: flipped.origin.y * viewSize.height,
            width: flipped.size.width * viewSize.width,
            height: flipped.size.height * viewSize.height
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
        coordinate.hostView = view
        AppLogger.runtime.debug("Created camera preview host view")
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer.session = session
        coordinate.hostView = uiView
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

    override func layoutSubviews() {
        super.layoutSubviews()
        applyOrientationRotation()
    }

    /// Updates the preview layer rotation to match the current interface orientation.
    /// landscapeLeft=180°, landscapeRight=0° — matches the output connection rotation
    /// set by CameraService.applyCurrentOrientation().
    private func applyOrientationRotation() {
        guard let connection = previewLayer.connection else { return }
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .landscapeRight
        let angle: CGFloat = orientation == .landscapeLeft ? 180 : 0
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Convert a normalised YOLO bounding rect to this view's coordinate space.
    /// Flips x/y to match Vision's metadata coordinate system, then calls
    /// layerRectConverted which accounts for preview rotation and gravity.
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
