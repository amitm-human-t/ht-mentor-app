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
    #if targetEnvironment(simulator)
    let bleManager = MockHandXBLEManager()
    #else
    let bleManager = HandXBLEManager()
    #endif
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

    func openUserChooser() {
        path.append(.userChooser)
    }

    /// Commits `user` as the active trainee and persists the selection.
    func selectUser(_ user: UserRecord) {
        selectedUser = user
        UserDefaultsStore.lastActiveUserID = user.id
    }

    /// Called from UserChooserView after a user is deleted.
    func userWasDeleted(id: UUID) {
        if selectedUser?.id == id {
            selectedUser = nil
            UserDefaultsStore.lastActiveUserID = nil
        }
    }

    func openResults(summary: RunSummaryDraft) {
        persistCompletedRun(summary: summary)
        path.append(.results(summary))
    }

    func openAnalysis(runID: UUID) {
        path.append(.analysis(runID))
    }

    func openLeaderboards() {
        path.append(.leaderboards)
    }

    func openReports() {
        path.append(.reports)
    }

    func openUserManagement() {
        path.append(.userManagement)
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
        let users = userRepository.fetchUsers()

        // Restore last active user by persisted ID
        if let lastID = UserDefaultsStore.lastActiveUserID,
           let match = users.first(where: { $0.id == lastID }) {
            selectedUser = match
            return
        }

        // Fall back to first existing user
        if let first = users.first {
            selectedUser = first
            UserDefaultsStore.lastActiveUserID = first.id
            return
        }

        // First-run: create a default trainee
        let user = UserRecord(displayName: "Trainee 1", dominantHandRawValue: DominantHand.right.rawValue)
        userRepository.insert(user)
        selectedUser = user
        UserDefaultsStore.lastActiveUserID = user.id
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
    case userChooser
    case taskPicker
    case taskRunner(TaskDefinition)
    case results(RunSummaryDraft)
    case analysis(UUID)
    case leaderboards
    case reports
    case userManagement
    case diagnostics
    case permissions
    case ble
}
