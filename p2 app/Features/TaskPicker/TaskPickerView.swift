import SwiftUI

struct TaskPickerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        List {
            if let reason = appModel.taskStartBlockReason {
                Section("Task Start Blocked") {
                    Text(reason)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(TaskDefinition.all, id: \.id) { task in
                VStack(alignment: .leading, spacing: 10) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(visibleModes(for: task), id: \.self) { mode in
                                Button(mode.rawValue.capitalized) {
                                    appModel.runnerCoordinator.prepare(task: task, mode: mode)
                                    appModel.startTask(task)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!appModel.canStartTasks)
                            }
                        }
                    }
                    if hiddenLockedSprint(task: task) {
                        Text("Locked Sprint is available after HandX connects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Task Picker")
    }

    private func visibleModes(for task: TaskDefinition) -> [TaskMode] {
        task.supportedModes.filter { mode in
            !(mode == .lockedSprint && appModel.bleManager.connectionState != .connected)
        }
    }

    private func hiddenLockedSprint(task: TaskDefinition) -> Bool {
        task.supportedModes.contains(.lockedSprint) && appModel.bleManager.connectionState != .connected
    }
}
