import SwiftUI
import AVFoundation

struct AppPreviewStageView: View {
    @Bindable var appModel: AppModel
    let showsControls: Bool
    let compact: Bool
    private let runnerCoordinator: RunnerCoordinator
    private let debugVideoFrameSource: DebugVideoFrameSource
    private let cameraService: CameraService

    /// Shared coordinate converter — populated when the camera preview UIView is ready.
    @State private var previewCoordinate = PreviewCoordinate()

    init(appModel: AppModel, showsControls: Bool = true, compact: Bool = false) {
        self.appModel = appModel
        self.showsControls = showsControls
        self.compact = compact
        self.runnerCoordinator = appModel.runnerCoordinator
        self.debugVideoFrameSource = appModel.debugVideoFrameSource
        self.cameraService = appModel.cameraService
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewSurface
                .background(Color.black)
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { newSize in
                    previewCoordinate.viewSize = newSize
                }
                .overlay {
                    PreviewOverlayView(
                        payload: runnerCoordinator.latestOutput.overlayPayload,
                        coordinateConverter: previewCoordinate.convert
                    )
                }
                .overlay {
                    #if DEBUG
                    if runnerCoordinator.debugBoundingBoxesVisible {
                        DebugDetectionOverlay(
                            detections: runnerCoordinator.debugAllDetections,
                            tip: runnerCoordinator.debugInstrumentTip,
                            coordinateConverter: previewCoordinate.convert
                        )
                    }
                    #endif
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 20 : 28, style: .continuous))

            if showsControls && appModel.previewControlsVisible {
                previewControls
                    .padding()
            }
        }
        .onAppear {
            appModel.refreshPreviewSource()
        }
        .onChange(of: runnerCoordinator.inputSource) { _, newValue in
            if newValue == .debugVideo {
                debugVideoFrameSource.selectPreferredVideo(for: appModel.currentTaskIdentifier)
            }
            appModel.refreshPreviewSource()
        }
        .onChange(of: runnerCoordinator.activeTask?.id) { _, newTask in
            debugVideoFrameSource.selectPreferredVideo(for: newTask)
            appModel.refreshPreviewSource()
        }
        .onChange(of: appModel.previewVisible) { _, _ in
            appModel.refreshPreviewSource()
        }
    }

    private var previewSurface: some View {
        Group {
            if !appModel.previewVisible {
                Color.black
            } else if runnerCoordinator.inputSource == .debugVideo {
                if let player = debugVideoFrameSource.previewPlayer {
                    DebugVideoPreviewView(player: player)
                } else {
                    Color.black
                }
            } else {
                CameraPreviewView(session: cameraService.session, coordinate: previewCoordinate)
                    .overlay {
                        if cameraService.authorizationStatus != .authorized {
                            Color.black.opacity(0.65)
                            Text("Camera access required")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $appModel.previewVisible) {
                Text("Preview")
                    .font(.headline)
            }
            .toggleStyle(.switch)

            if appModel.previewVisible {
                Picker("Source", selection: inputSourceBinding) {
                    ForEach(RunnerCoordinator.InputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if runnerCoordinator.inputSource == .debugVideo {
                    Picker("Embedded Video", selection: embeddedVideoSelection) {
                        ForEach(appModel.embeddedVideosForCurrentTask) { video in
                            Text(video.name).tag(Optional(video.url))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: compact ? 300 : 340, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var embeddedVideoSelection: Binding<URL?> {
        Binding(
            get: { debugVideoFrameSource.selectedVideoURL },
            set: { newValue in
                guard let newValue else { return }
                debugVideoFrameSource.selectVideo(url: newValue)
            }
        )
    }

    private var inputSourceBinding: Binding<RunnerCoordinator.InputSource> {
        Binding(
            get: { runnerCoordinator.inputSource },
            set: { runnerCoordinator.inputSource = $0 }
        )
    }
}

private struct PreviewOverlayView: View {
    let payload: OverlayPayload
    /// Converts normalised YOLO rects to view coordinates via AVCaptureVideoPreviewLayer.
    /// Falls back to flip-based approximation when the live camera is not active.
    let coordinateConverter: (CGRect) -> CGRect

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(payload.elements.enumerated()), id: \.offset) { _, element in
                    switch element {
                    case .box(let rect, let label, let color):
                        boxOverlay(rect: rect, label: label, color: color, in: proxy.size)
                    case .line(let start, let end, let label):
                        lineOverlay(start: start, end: end, label: label, in: proxy.size)
                    case .target(let center, let radius, let label):
                        targetOverlay(center: center, radius: radius, label: label, in: proxy.size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func boxOverlay(rect: CGRect, label: String, color: OverlayColor, in size: CGSize) -> some View {
        let mapped = mapYOLO(rect: rect, into: size)
        if mapped.width > 1 && mapped.height > 1 &&
           mapped.width.isFinite && mapped.height.isFinite &&
           mapped.origin.x.isFinite && mapped.origin.y.isFinite {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(color.swiftUIColor, lineWidth: 2.5)
                    .frame(width: mapped.width, height: mapped.height)
                    .position(x: mapped.midX, y: mapped.midY)

                Text(label)
                    .font(.hxCaption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .foregroundStyle(color.swiftUIColor)
                    .position(x: mapped.minX + max(36, mapped.width / 2), y: max(12, mapped.minY - 13))
            }
        }
    }

    private func lineOverlay(start: CGPoint, end: CGPoint, label: String?, in size: CGSize) -> some View {
        let mappedStart = mapPoint(start, into: size)
        let mappedEnd = mapPoint(end, into: size)
        return ZStack {
            Path { path in
                path.move(to: mappedStart)
                path.addLine(to: mappedEnd)
            }
            .stroke(Color.hxAmber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))

            if let label {
                Text(label)
                    .font(.hxCaption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .foregroundStyle(Color.hxAmber)
                    .position(x: (mappedStart.x + mappedEnd.x) / 2, y: (mappedStart.y + mappedEnd.y) / 2 - 14)
            }
        }
    }

    private func targetOverlay(center: CGPoint, radius: CGFloat, label: String, in size: CGSize) -> some View {
        let mappedCenter = mapPoint(center, into: size)
        let scaledRadius = max(10, radius * min(size.width, size.height))
        return ZStack {
            Circle()
                .stroke(Color.hxCyan, lineWidth: 2.5)
                .frame(width: scaledRadius * 2, height: scaledRadius * 2)
                .position(mappedCenter)

            Text(label)
                .font(.hxCaption)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.78), in: Capsule())
                .foregroundStyle(Color.hxCyan)
                .position(x: mappedCenter.x, y: mappedCenter.y - scaledRadius - 14)
        }
    }

    // MARK: - Coordinate Mapping


    /// Map a normalised YOLO rect through the preview layer coordinate converter,
    /// then scale to the SwiftUI view size.
    private func mapYOLO(rect: CGRect, into size: CGSize) -> CGRect {
        // coordinateConverter returns a rect in the [0,1] normalised layer space
        // (i.e., it still needs to be scaled to the actual pixel size).
        // PreviewCoordinate.convert handles the metadata flip then calls layerRectConverted,
        // which returns a rect in *layer* pixel coordinates — NOT 0..1.
        // So we must NOT multiply by size here; instead we return the rect directly.
        coordinateConverter(rect)
    }

    private func mapPoint(_ point: CGPoint, into size: CGSize) -> CGPoint {
        // Points for lines/targets are still in normalised 0..1 space — scale to view.
        // Apply same flip as YOLO rects for consistency.
        let flipped = CGPoint(x: 1.0 - point.x, y: 1.0 - point.y)
        return CGPoint(x: flipped.x * size.width, y: flipped.y * size.height)
    }
}

// MARK: - Debug Detection Overlay (DEBUG builds only)

#if DEBUG
/// Draws raw YOLO bounding boxes and the instrument tip as amber/cyan overlays.
/// Uses the same coordinate converter as PreviewOverlayView so boxes align
/// correctly with the camera preview.
private struct DebugDetectionOverlay: View {
    let detections: [TaskDetection]
    let tip: InstrumentTipPayload?
    let coordinateConverter: (CGRect) -> CGRect

    var body: some View {
        ZStack {
            ForEach(detections) { detection in
                let rect = coordinateConverter(detection.boundingBox)
                if rect.width > 1 && rect.height > 1 &&
                   rect.width.isFinite && rect.height.isFinite &&
                   rect.origin.x.isFinite && rect.origin.y.isFinite {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.hxAmber.opacity(0.75), lineWidth: 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        Text("\(detection.label) \(Int(detection.confidence * 100))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.hxAmber)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .position(x: rect.midX, y: max(10, rect.minY - 9))
                    }
                }
            }

            if let tip {
                let tipRect = coordinateConverter(CGRect(
                    x: tip.location.x - 0.015,
                    y: tip.location.y - 0.015,
                    width: 0.03,
                    height: 0.03
                ))
                if tipRect.midX.isFinite && tipRect.midY.isFinite {
                    Circle()
                        .fill(Color.hxCyan.opacity(0.8))
                        .frame(width: 10, height: 10)
                        .position(x: tipRect.midX, y: tipRect.midY)
                    Circle()
                        .stroke(Color.hxCyan, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .position(x: tipRect.midX, y: tipRect.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
