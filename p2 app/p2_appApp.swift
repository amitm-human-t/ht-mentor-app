import SwiftUI
import SwiftData

@main
struct p2_appApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            UserRecord.self,
            RunSummaryRecord.self
        ])
    }
}
