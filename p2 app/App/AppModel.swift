import SwiftUI
import SwiftData
import OSLog

@Observable
@MainActor
final class AppModel {
    var path: [AppRoute] = []
    var diagnostics = StartupDiagnostics()
    var selectedUser: UserRecord?
    var deviceSupport = DeviceSupportSnapshot.current()
    var previewVisible = true
    var previewControlsVisible = true

    let permissionCenter = PermissionCenter()
    let cameraService = CameraService()
    let debugVideoFrameSource = DebugVideoFrameSource()
    let bleManager = HandXBLEManager()
    let audioService = AudioService()
    let modelRegistry = CoreMLModelRegistry()
    let frameBus = CameraFrameBus()

    @ObservationIgnored
    private(set) lazy var runnerCoordinator = RunnerCoordinator(
        cameraService: cameraService,
        debugVideoFrameSource: debugVideoFrameSource,
        bleManager: bleManager,
        modelRegistry: modelRegistry,
        permissionCenter: permissionCenter,
        frameBus: frameBus
    )

    private var userRepository: UserRepository?
    private var runSummaryRepository: RunSummaryRepository?
    private var leaderboardRepository: LeaderboardRepository?

    func configure(modelContext: ModelContext) {
        guard userRepository == nil else { return }
        userRepository = UserRepository(modelContext: modelContext)
        runSummaryRepository = RunSummaryRepository(modelContext: modelContext)
        leaderboardRepository = LeaderboardRepository(modelContext: modelContext)
        seedDefaultUserIfNeeded()
    }

    func bootstrap() async {
        _ = await permissionCenter.refresh()
        await cameraService.refreshAuthorizationStatus()
        debugVideoFrameSource.refreshBundledVideos()
        diagnostics = await StartupDiagnostics.run(
            bundle: .main,
            assetCatalog: AssetCatalog.production
        )
        deviceSupport = DeviceSupportSnapshot.current()
    }

    func openTaskPicker() {
        path.append(.taskPicker)
    }

    func openDiagnostics() {
        path.append(.diagnostics)
    }

    func openPermissions() {
        path.append(.permissions)
    }

    func openBLEConsole() {
        path.append(.ble)
    }

    func startTask(_ task: TaskDefinition) {
        guard canStartTasks else {
            openDiagnostics()
            return
        }
        debugVideoFrameSource.selectPreferredVideo(for: task.id)
        path.append(.taskRunner(task))
    }

    func persistCompletedRun(summary: RunSummaryDraft) {
        guard let runSummaryRepository else { return }
        runSummaryRepository.save(summary: summary)
    }

    private func seedDefaultUserIfNeeded() {
        guard let userRepository else { return }
        if let existing = userRepository.fetchUsers().first {
            selectedUser = existing
            return
        }
        let user = UserRecord(displayName: "Default Trainee", dominantHandRawValue: DominantHand.right.rawValue)
        userRepository.insert(user)
        selectedUser = user
    }

    var canStartTasks: Bool {
        diagnostics.isHealthy
    }

    var taskStartBlockReason: String? {
        guard !diagnostics.isHealthy else { return nil }
        return "Task start is blocked until missing model and sound assets are fixed."
    }

    var currentTaskIdentifier: TaskIdentifier? {
        runnerCoordinator.activeTask?.id
    }

    var embeddedVideosForCurrentTask: [DebugVideoFrameSource.BundledVideo] {
        debugVideoFrameSource.preferredVideos(for: currentTaskIdentifier)
    }

    func refreshPreviewSource() {
        guard previewVisible else {
            cameraService.stopSession()
            debugVideoFrameSource.stop()
            return
        }

        switch runnerCoordinator.inputSource {
        case .liveCamera:
            Task {
                do {
                    try await cameraService.startSession(frameBus: frameBus)
                } catch {
                    AppLogger.runtime.error("Preview camera start failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .debugVideo:
            debugVideoFrameSource.selectPreferredVideo(for: currentTaskIdentifier)
            cameraService.stopSession()
        }
    }
}

enum AppRoute: Hashable {
    case taskPicker
    case taskRunner(TaskDefinition)
    case diagnostics
    case permissions
    case ble
}
