import SwiftUI

/// Collapsible trailing panel shown during a run.
/// Contains five DisclosureGroup sections: Run Controls, Trainer Actions,
/// Debug, Video Source, and HandX Live.
struct TrainerControlsPanel: View {
    let appModel: AppModel
    let taskDefinition: TaskDefinition
    @Binding var selectedMode: TaskMode
    @Binding var isVisible: Bool

    // Section expansion state
    @State private var runControlsOpen = true
    @State private var trainerActionsOpen = true
    @State private var videoSourceOpen = false
    @State private var handXOpen = false
    @State private var debugOpen = false

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().background(Color.hxSurfaceBorder)
            ScrollView(showsIndicators: false) {
                VStack(spacing: HXSpacing.sm) {
                    runControlsSection
                    trainerActionsSection
                    videoSourceSection
                    handXLiveSection
                    debugSection
                }
                .padding(HXSpacing.lg)
            }
        }
        .background(Color.hxSurface.ignoresSafeArea())
        .frame(width: 320)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            Text("Controls")
                .font(.hxTitle3)
                .foregroundStyle(.white)
            Spacer()
            Button {
                withAnimation(.hxPanel) { isVisible = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.hxSurfaceBorder)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HXSpacing.lg)
        .padding(.vertical, HXSpacing.md)
    }

    // MARK: - Section 1: Run Controls

    private var runControlsSection: some View {
        PanelSection(title: "Run Controls", isOpen: $runControlsOpen) {
            let phase = coordinator.stateMachine.phase

            VStack(spacing: HXSpacing.sm) {
                // Primary action
                if phase == .idle || phase == .finished || phase == .error {
                    Button {
                        Task { await coordinator.start() }
                    } label: {
                        Group {
                            if coordinator.isModelLoading {
                                HStack(spacing: 6) {
                                    ProgressView().tint(.white).scaleEffect(0.75)
                                    Text("Loading…")
                                }
                            } else {
                                Label("Start", systemImage: "play.fill")
                            }
                        }
                        .font(.hxHeadline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.hxCyan)
                    .disabled(coordinator.isModelLoading)
                } else if phase == .running {
                    Button {
                        coordinator.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.hxHeadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.hxAmber)
                } else if phase == .paused {
                    Button {
                        coordinator.resume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.hxHeadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.hxSuccess)
                }

                // Mode picker
                if taskDefinition.supportedModes.count > 1 {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(taskDefinition.supportedModes, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMode) { _, newValue in
                        coordinator.prepare(task: taskDefinition, mode: newValue)
                    }
                }

                // Secondary: Reset + End
                HStack(spacing: HXSpacing.sm) {
                    Button {
                        coordinator.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.hxCallout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(phase == .idle)

                    Button {
                        coordinator.finish()
                    } label: {
                        Label("End Run", systemImage: "xmark.circle")
                            .font(.hxCallout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(Color.hxDanger)
                    .disabled(phase == .idle)
                }
            }
        }
    }

    // MARK: - Section 2: Trainer Actions

    private var trainerActionsSection: some View {
        PanelSection(title: "Trainer Actions", isOpen: $trainerActionsOpen) {
            VStack(spacing: HXSpacing.sm) {
                HStack(spacing: HXSpacing.sm) {
                    trainerActionButton("Skip Target", icon: "forward.fill", tint: Color.hxCyan, action: .skipTarget)
                    trainerActionButton("Mark Success", icon: "checkmark.circle.fill", tint: Color.hxSuccess, action: .markSuccess)
                }
                HStack(spacing: HXSpacing.sm) {
                    trainerActionButton("Mark Failure", icon: "xmark.circle.fill", tint: Color.hxDanger, action: .markFailure)
                    trainerActionButton("Key Dropped", icon: "arrow.down.circle.fill", tint: Color.hxWarning, action: .keyDropped)
                }
            }
        }
    }

    private func trainerActionButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: TrainerAction.Kind
    ) -> some View {
        Button {
            coordinator.registerTrainerAction(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.hxCaption)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HXSpacing.md)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 3: Video Source

    private var videoSourceSection: some View {
        PanelSection(title: "Preview Source", isOpen: $videoSourceOpen) {
            VStack(alignment: .leading, spacing: HXSpacing.sm) {
                Picker("Source", selection: inputSourceBinding) {
                    ForEach(RunnerCoordinator.InputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if coordinator.inputSource == .debugVideo {
                    Picker("Embedded Video", selection: embeddedVideoBinding) {
                        ForEach(appModel.embeddedVideosForCurrentTask) { video in
                            Text(video.name).tag(Optional(video.url))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.hxCyan)
                } else {
                    Toggle(isOn: torchBinding) {
                        HStack(spacing: 6) {
                            Image(systemName: appModel.cameraService.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                                .foregroundStyle(appModel.cameraService.torchEnabled ? Color.hxAmber : .white.opacity(0.65))
                            Text("Torch")
                                .font(.hxCaption)
                        }
                    }
                    .tint(Color.hxAmber)
                    .disabled(!appModel.cameraService.torchAvailable)

                    if !appModel.cameraService.torchAvailable {
                        Text("Torch unavailable on this device/input")
                            .font(.hxCaption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    // MARK: - Section 4: HandX Live

    private var handXLiveSection: some View {
        PanelSection(title: "HandX Live", isOpen: $handXOpen) {
            let sample = appModel.bleManager.latestSample
            VStack(alignment: .leading, spacing: HXSpacing.sm) {
                dataRow("Connected", value: sample.connected ? "Yes" : "No",
                        valueColor: sample.connected ? Color.hxSuccess : Color.hxDanger)
                dataRow("Joystick X", value: sample.joystick.x.formatted(.number.precision(.fractionLength(2))))
                dataRow("Joystick Y", value: sample.joystick.y.formatted(.number.precision(.fractionLength(2))))
                dataRow("Orientation", value: "\(Int(sample.orientation.x))° \(Int(sample.orientation.y))° \(Int(sample.orientation.z))°")
                dataRow("Grip", value: sample.grip.formatted(.number.precision(.fractionLength(2))))
            }
        }
    }

    // MARK: - Section 5: Debug

    private var debugSection: some View {
        PanelSection(title: "Debug", isOpen: $debugOpen) {
            VStack(alignment: .leading, spacing: HXSpacing.sm) {
                dataRow("Phase", value: coordinator.stateMachine.phase.rawValue)
                dataRow("Thermal", value: appModel.thermalMonitor.displayName,
                        valueColor: thermalColor)
                dataRow("Detections", value: "\(coordinator.latestInferenceStatus.taskDetectionCount)")
                dataRow("Task Model", value: coordinator.latestInferenceStatus.taskModelLoaded ? "Loaded" : "Loading…")
                dataRow("Instr. Model", value: coordinator.latestInferenceStatus.instrumentModelLoaded ? "Loaded" : "Loading…")
                if let failure = coordinator.currentFailure {
                    Text(failure.localizedDescription ?? "Error")
                        .font(.hxCaption)
                        .foregroundStyle(Color.hxDanger)
                        .lineLimit(3)
                }
                #if DEBUG
                Divider().background(Color.hxSurfaceBorder)
                Text("YOLO Debug")
                    .font(.hxCaption)
                    .foregroundStyle(.white.opacity(0.60))

                Toggle(isOn: Binding(
                    get: { coordinator.debugBoundingBoxesVisible },
                    set: { _ in coordinator.toggleDebugBoundingBoxes() }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.dashed")
                            .foregroundStyle(Color.hxAmber)
                        Text("Raw Bounding Boxes")
                            .font(.hxCaption)
                    }
                }
                .tint(Color.hxAmber)
                if coordinator.debugBoundingBoxesVisible {
                    dataRow("Raw Detects", value: "\(coordinator.debugAllDetections.count)")
                    dataRow("Instr. Tip", value: coordinator.debugInstrumentTip != nil ? "Detected" : "None")
                }

                thresholdSliderRow(
                    label: "Conf",
                    value: Double(UserDefaultsStore.confidenceThreshold),
                    range: 0.05...0.95,
                    valueText: "\(Int(UserDefaultsStore.confidenceThreshold * 100))%"
                ) { newValue in
                    UserDefaultsStore.confidenceThreshold = Float(newValue)
                }

                thresholdSliderRow(
                    label: "IoU",
                    value: Double(UserDefaultsStore.iouThreshold),
                    range: 0.05...0.95,
                    valueText: String(format: "%.2f", UserDefaultsStore.iouThreshold)
                ) { newValue in
                    UserDefaultsStore.iouThreshold = Float(newValue)
                }

                Toggle(isOn: Binding(
                    get: { coordinator.debugImageProcessingVisible },
                    set: { _ in coordinator.toggleDebugImageProcessing() }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.filters")
                            .foregroundStyle(Color.hxCyan)
                        Text("Image Processing Overlay")
                            .font(.hxCaption)
                    }
                }
                .tint(Color.hxCyan)
                if coordinator.debugImageProcessingVisible {
                    dataRow("Algo Elements", value: "\(coordinator.debugImageProcessingPayload.elements.count)")
                }

                if taskDefinition.id == .keyLock {
                    Toggle(isOn: Binding(
                        get: { coordinator.debugKeyLockRedPatchVisible },
                        set: { _ in coordinator.toggleDebugKeyLockRedPatch() }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                                .foregroundStyle(Color.hxDanger)
                            Text("KeyLock Red% + Bin Contour")
                                .font(.hxCaption)
                        }
                    }
                    .tint(Color.hxDanger)
                    if coordinator.debugKeyLockRedPatchVisible {
                        dataRow("RedPatch Elements", value: "\(coordinator.debugKeyLockRedPatchPayload.elements.count)")
                    }
                }

                if taskDefinition.id == .keyLock {
                    Divider().background(Color.hxSurfaceBorder)
                    Text("Algorithm Debug · KeyLockV2")
                        .font(.hxCaption)
                        .foregroundStyle(.white.opacity(0.60))

                    thresholdSliderRow(
                        label: "Red %",
                        value: Double(UserDefaultsStore.keyLockSlotOverlapThreshold),
                        range: 10...100,
                        valueText: "\(Int(UserDefaultsStore.keyLockSlotOverlapThreshold))%"
                    ) { newValue in
                        UserDefaultsStore.keyLockSlotOverlapThreshold = Float(newValue)
                    }

                    thresholdSliderRow(
                        label: "Hold",
                        value: Double(UserDefaultsStore.keyLockHoldDurationSeconds),
                        range: 0.10...2.50,
                        valueText: String(format: "%.2fs", UserDefaultsStore.keyLockHoldDurationSeconds)
                    ) { newValue in
                        UserDefaultsStore.keyLockHoldDurationSeconds = Float(newValue)
                    }

                    Toggle(isOn: Binding(
                        get: { UserDefaultsStore.keyLockInvertYOrdering },
                        set: { UserDefaultsStore.keyLockInvertYOrdering = $0 }
                    )) {
                        Text("Invert Y Slot Ordering")
                            .font(.hxCaption)
                    }
                    .tint(Color.hxAmber)
                }
                #endif
            }
        }
    }

    // MARK: - Shared helpers

    private var coordinator: RunnerCoordinator { appModel.runnerCoordinator }

    private var thermalColor: Color {
        switch appModel.thermalMonitor.thermalState {
        case .nominal, .fair: return .white
        case .serious:        return Color.hxWarning
        case .critical:       return Color.hxDanger
        @unknown default:     return .white
        }
    }

    @ViewBuilder
    private func dataRow(_ label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.hxCaption)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.hxMonoCaption)
                .foregroundStyle(valueColor)
        }
    }

    @ViewBuilder
    private func thresholdSliderRow(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        valueText: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            dataRow(label, value: valueText)
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            .tint(Color.hxCyan)
        }
    }

    private var inputSourceBinding: Binding<RunnerCoordinator.InputSource> {
        Binding(
            get: { coordinator.inputSource },
            set: { newSource in
                Task { await coordinator.switchInputSource(to: newSource) }
            }
        )
    }

    private var embeddedVideoBinding: Binding<URL?> {
        Binding(
            get: { appModel.debugVideoFrameSource.selectedVideoURL },
            set: { url in
                guard let url else { return }
                appModel.debugVideoFrameSource.selectVideo(url: url)
            }
        )
    }

    private var torchBinding: Binding<Bool> {
        Binding(
            get: { appModel.cameraService.torchEnabled },
            set: { isOn in
                appModel.cameraService.setTorchEnabled(isOn)
            }
        )
    }
}

// MARK: - PanelSection

/// Reusable collapsible section with chevron indicator.
private struct PanelSection<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.hxDefault) { isOpen.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(.hxCaption)
                        .foregroundStyle(.white.opacity(0.40))
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.hxSurfaceBorder)
                }
                .padding(.vertical, HXSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                content
                    .padding(.top, HXSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HXSpacing.md)
        .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.md))
    }
}
