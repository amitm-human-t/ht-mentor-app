import SwiftUI

struct HubView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                previewCard
                deviceSupportCard
                diagnosticsCard
                permissionCard
                quickActions
            }
            .padding(24)
        }
        .navigationTitle("HandX Training Hub")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iPad runtime bootstrap")
                .font(.largeTitle.bold())
            Text("Camera, BLE, models, and runner state are wired as the first milestone shell.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var diagnosticsCard: some View {
        StatusCard(
            title: "Startup diagnostics",
            subtitle: appModel.diagnostics.isHealthy ? "All required startup assets were found." : "\(appModel.diagnostics.missingEntries.count) bundled assets are missing. Task start is blocked until they are fixed.",
            accent: appModel.diagnostics.isHealthy ? .green : .orange
        ) {
            Button("Open Diagnostics") {
                appModel.openDiagnostics()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var previewCard: some View {
        StatusCard(
            title: "Preview",
            subtitle: "Rear-camera or embedded debug video preview with live overlay status.",
            accent: appModel.runnerCoordinator.inputSource == .liveCamera ? .green : .blue
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AppPreviewStageView(appModel: appModel, showsControls: true, compact: true)
                    .frame(height: 220)

                Text(previewStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceSupportCard: some View {
        StatusCard(
            title: appModel.deviceSupport.title,
            subtitle: "\(appModel.deviceSupport.message)\nIdentifier: \(appModel.deviceSupport.hardwareIdentifier)",
            accent: appModel.deviceSupport.level == .supported ? .green : .orange
        ) {
            EmptyView()
        }
    }

    private var permissionCard: some View {
        StatusCard(
            title: "Permissions",
            subtitle: "Camera: \(appModel.permissionCenter.snapshot.camera.rawValue) • Bluetooth: \(appModel.permissionCenter.snapshot.bluetooth.rawValue)",
            accent: appModel.permissionCenter.snapshot.camera == .authorized ? .green : .orange
        ) {
            Button("Permission Center") {
                appModel.openPermissions()
            }
            .buttonStyle(.bordered)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ActionTile(
                    title: "Start Task",
                    subtitle: appModel.canStartTasks ? "Pick a task and mode" : "Task start blocked until diagnostics are green"
                ) {
                    if appModel.canStartTasks {
                        appModel.openTaskPicker()
                    } else {
                        appModel.openDiagnostics()
                    }
                }
                ActionTile(title: "HandX Console", subtitle: appModel.bleManager.statusText) {
                    appModel.openBLEConsole()
                }
                ActionTile(title: "Task Runner Shell", subtitle: "Open directly into KeyLock") {
                    appModel.runnerCoordinator.prepare(task: TaskDefinition.all[0], mode: .guided)
                    appModel.startTask(TaskDefinition.all[0])
                }
            }
        }
    }

    private var previewStatusText: String {
        switch appModel.runnerCoordinator.inputSource {
        case .liveCamera:
            return "Live camera preview is active from the single shared camera service."
        case .debugVideo:
            return "Embedded debug video: \(appModel.debugVideoFrameSource.selectedVideoURL?.lastPathComponent ?? "Not selected")"
        }
    }
}

private struct ActionTile: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct StatusCard<Actions: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.title3.bold())
            }
            Text(subtitle)
                .foregroundStyle(.secondary)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
