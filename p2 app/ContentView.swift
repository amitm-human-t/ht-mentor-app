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
                    case .taskPicker:
                        TaskPickerView(appModel: appModel)
                    case .taskRunner(let task):
                        TaskRunnerView(appModel: appModel, taskDefinition: task)
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
