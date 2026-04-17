import SwiftUI
import AVFoundation

struct AppPreviewStageView: View {
    @Bindable var appModel: AppModel
    let showsControls: Bool
    let compact: Bool
    private let runnerCoordinator: RunnerCoordinator
    private let debugVideoFrameSource: DebugVideoFrameSource
    private let cameraService: CameraService

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
                .overlay {
                    PreviewOverlayView(payload: runnerCoordinator.latestOutput.overlayPayload)
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
                CameraPreviewView(session: cameraService.session)
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(payload.elements.enumerated()), id: \.offset) { _, element in
                    switch element {
                    case .box(let rect, let label):
                        boxOverlay(rect: rect, label: label, in: proxy.size)
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

    private func boxOverlay(rect: CGRect, label: String, in size: CGSize) -> some View {
        let mapped = map(rect: rect, into: size)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: mapped.width, height: mapped.height)
                .position(x: mapped.midX, y: mapped.midY)

            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72), in: Capsule())
                .foregroundStyle(.white)
                .position(x: mapped.minX + 72, y: max(14, mapped.minY - 12))
        }
    }

    private func lineOverlay(start: CGPoint, end: CGPoint, label: String?, in size: CGSize) -> some View {
        let mappedStart = map(point: start, into: size)
        let mappedEnd = map(point: end, into: size)
        return ZStack {
            Path { path in
                path.move(to: mappedStart)
                path.addLine(to: mappedEnd)
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 8]))

            if let label {
                Text(label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(.white)
                    .position(x: (mappedStart.x + mappedEnd.x) / 2, y: (mappedStart.y + mappedEnd.y) / 2 - 16)
            }
        }
    }

    private func targetOverlay(center: CGPoint, radius: CGFloat, label: String, in size: CGSize) -> some View {
        let mappedCenter = map(point: center, into: size)
        let scaledRadius = max(10, radius * min(size.width, size.height))
        return ZStack {
            Circle()
                .stroke(Color.cyan, lineWidth: 3)
                .frame(width: scaledRadius * 2, height: scaledRadius * 2)
                .position(mappedCenter)

            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72), in: Capsule())
                .foregroundStyle(.white)
                .position(x: mappedCenter.x, y: mappedCenter.y - scaledRadius - 16)
        }
    }

    private func map(rect: CGRect, into size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    private func map(point: CGPoint, into size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
