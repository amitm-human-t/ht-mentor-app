import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: StartupDiagnostics

    var body: some View {
        List {
            Section("Assets") {
                ForEach(diagnostics.entries) { entry in
                    HStack {
                        Image(systemName: entry.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(entry.found ? Color.hxSuccess : Color.hxAmber)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.asset.displayName)
                                .font(.hxBody)
                            Text(entry.found ? "Present" : "Missing from main bundle")
                                .font(.hxCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Logs") {
                NavigationLink(destination: LogViewerView()) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(Color.hxCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Logs")
                                .font(.hxBody)
                            Text("Live view of handx-debug.log — auto-refreshes every 2 s")
                                .font(.hxCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
