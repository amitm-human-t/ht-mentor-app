import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appModel = AppModel()

    var body: some View {
        NavigationStack(path: $appModel.path) {
            HubView(appModel: appModel)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .userChooser:
                        UserChooserView(appModel: appModel)
                    case .taskPicker:
                        TaskPickerView(appModel: appModel)
                    case .taskRunner(let task):
                        TaskRunnerView(appModel: appModel, taskDefinition: task)
                    case .results(let summary):
                        ResultsView(summary: summary, appModel: appModel)
                    case .analysis(let runID):
                        AnalysisView(runID: runID, appModel: appModel)
                    case .leaderboards:
                        LeaderboardsView(appModel: appModel)
                    case .reports:
                        ReportsView(appModel: appModel)
                    case .userManagement:
                        UserManagementView(appModel: appModel)
                    case .diagnostics:
                        DiagnosticsView(diagnostics: appModel.diagnostics)
                    case .permissions:
                        PermissionCenterView(permissionCenter: appModel.permissionCenter)
                    case .ble:
                        BLEConsoleView(bleManager: appModel.bleManager)
                    }
                }
        }
        .task {
            appModel.configure(modelContext: modelContext)
            await appModel.bootstrap()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            UserRecord.self,
            RunSummaryRecord.self
        ], inMemory: true)
}
