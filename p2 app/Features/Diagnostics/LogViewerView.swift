import SwiftUI
import Combine

struct LogViewerView: View {
    @State private var logText: String = ""
    @State private var showShareSheet = false
    @State private var autoScroll = true
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if logText.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                                logLineView(line)
                                    .id(idx)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: logText) { _, _ in
                    if autoScroll {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            floatingToolbar
        }
        .background(Color.hxBackground)
        .navigationTitle("App Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { reload() }
        .onReceive(timer) { _ in reload() }
        .sheet(isPresented: $showShareSheet) {
            if let url = logFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.hxSurfaceBorder)
            Text("No logs yet")
                .font(.hxHeadline)
                .foregroundStyle(Color.secondary)
            Text("Logs appear here as the app runs.\nErrors and warnings always write to file;\ninfo-level writes in DEBUG builds only.")
                .font(.hxCaption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func logLineView(_ line: String) -> some View {
        let level = logLevel(for: line)
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(level.accentColor)
                .frame(width: 2)
                .cornerRadius(1)
            Text(line)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(level.textColor)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }

    private var floatingToolbar: some View {
        HStack(spacing: 10) {
            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "arrow.down.to.line" : "pause.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(autoScroll ? Color.hxCyan : Color.hxAmber)
                    .frame(width: 36, height: 36)
                    .background(Color.hxSurfaceRaised.opacity(0.9))
                    .clipShape(Circle())
            }
        }
        .padding(16)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                UIPasteboard.general.string = logText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.hxCaption)
            }
            .tint(Color.hxCyan)

            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.hxCaption)
            }
            .tint(Color.hxCyan)

            Button(role: .destructive) {
                DebugLogFile.shared.clear()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { reload() }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.hxCaption)
            }
            .tint(Color.hxDanger)
        }
    }

    // MARK: - Helpers

    private var logLines: [String] {
        logText.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private var logFileURL: URL? {
        DebugLogFile.shared.url
    }

    private func reload() {
        let fresh = DebugLogFile.shared.contents
        if fresh != logText { logText = fresh }
    }

    private enum LogLevel {
        case fault, error, warn, info, other

        var accentColor: Color {
            switch self {
            case .fault:  return Color.hxDanger
            case .error:  return Color.hxDanger.opacity(0.7)
            case .warn:   return Color.hxAmber
            case .info:   return Color.hxCyan.opacity(0.6)
            case .other:  return Color.hxSurfaceBorder
            }
        }

        var textColor: Color {
            switch self {
            case .fault:  return Color.hxDanger
            case .error:  return Color.hxWarning
            case .warn:   return Color.hxAmber
            case .info:   return Color.primary
            case .other:  return Color.secondary
            }
        }
    }

    private func logLevel(for line: String) -> LogLevel {
        if line.contains("[FAULT]") { return .fault }
        if line.contains("[ERROR]") { return .error }
        if line.contains("[WARN]")  { return .warn }
        if line.contains("[INFO]")  { return .info }
        return .other
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
