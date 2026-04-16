import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: StartupDiagnostics

    var body: some View {
        List(diagnostics.entries) { entry in
            HStack {
                Image(systemName: entry.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(entry.found ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.asset.displayName)
                    Text(entry.found ? "Present" : "Missing from main bundle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
