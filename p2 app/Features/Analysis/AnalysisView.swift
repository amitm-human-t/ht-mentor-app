import SwiftUI
import SwiftData
import Charts

// MARK: - AnalysisView

struct AnalysisView: View {
    let runID: UUID
    let appModel: AppModel

    @Query(sort: \RunSummaryRecord.startedAt, order: .forward)
    private var allRuns: [RunSummaryRecord]

    @State private var selectedTab: AnalysisTab = .overview
    @State private var notes: String = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: Computed data

    private var run: RunSummaryRecord? {
        allRuns.first { $0.id == runID }
    }

    /// All runs by the same user on the same task, chronologically
    private var historyRuns: [RunSummaryRecord] {
        guard let run else { return [] }
        return allRuns.filter {
            $0.taskID == run.taskID && $0.userID == run.userID
        }
    }

    private var taskTitle: String {
        guard let run else { return "Run" }
        return TaskDefinition.all.first { $0.id.rawValue == run.taskID }?.title ?? run.taskID
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.hxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // Tab bar
                tabBar
                    .padding(.vertical, HXSpacing.sm)

                Divider()
                    .background(Color.hxSurfaceBorder)

                // Tab content
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            notes = UserDefaults.standard.string(forKey: "run.notes.\(runID.uuidString)") ?? ""
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                    Text(taskTitle)
                        .font(.hxCallout)
                }
                .foregroundStyle(Color.hxCyan)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("ANALYSIS")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(1.5)

            Spacer()

            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: HXSpacing.xs) {
            ForEach(AnalysisTab.allCases) { tab in
                AnalysisTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    onTap: {
                        withAnimation(.hxDefault) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal, HXSpacing.xl)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            OverviewTab(run: run, historyRuns: historyRuns)
        case .details:
            DetailsTab(run: run)
        case .handx:
            HandXTab(run: run)
        case .notes:
            NotesTab(runID: runID, notes: $notes)
        }
    }
}

// MARK: - Analysis Tab Enum

enum AnalysisTab: String, CaseIterable, Identifiable {
    case overview  = "Overview"
    case details   = "Details"
    case handx     = "HandX"
    case notes     = "Notes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .details:  return "list.bullet.rectangle"
        case .handx:    return "bolt.horizontal.fill"
        case .notes:    return "note.text"
        }
    }
}

// MARK: - Tab Button

private struct AnalysisTabButton: View {
    let tab: AnalysisTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.caption.weight(.semibold))
                Text(tab.rawValue)
                    .font(.hxCallout)
            }
            .foregroundStyle(isSelected ? .white : Color(white: 0.5))
            .padding(.horizontal, HXSpacing.md)
            .padding(.vertical, HXSpacing.sm)
            .background(
                isSelected
                    ? Color.hxCyan.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: HXRadius.sm)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HXRadius.sm)
                    .strokeBorder(
                        isSelected ? Color.hxCyan.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.hxDefault, value: isSelected)
    }
}

// MARK: - Overview Tab

private struct OverviewTab: View {
    let run: RunSummaryRecord?
    let historyRuns: [RunSummaryRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: HXSpacing.xl) {
                // This-run summary row
                if let run {
                    runSummaryRow(run: run)
                }

                // Score history chart
                scoreHistoryChart
                    .padding(.horizontal, HXSpacing.xl)

                // Personal bests
                if !historyRuns.isEmpty {
                    personalBests
                        .padding(.horizontal, HXSpacing.xl)
                }

                Spacer(minLength: HXSpacing.xl)
            }
            .padding(.top, HXSpacing.xl)
        }
    }

    // This-run quick stats
    private func runSummaryRow(run: RunSummaryRecord) -> some View {
        HStack(spacing: HXSpacing.md) {
            AnalysisStatTile(label: "Score", value: "\(run.score)", color: Color.hxCyan)
            AnalysisStatTile(label: "Targets", value: "\(run.completedTargets)/\(run.totalTargets)", color: Color.hxAmber)
            AnalysisStatTile(label: "Accuracy", value: accuracyText(run), color: Color.hxSuccess)
            AnalysisStatTile(label: "Duration", value: durationText(run), color: Color(white: 0.6))
        }
        .padding(.horizontal, HXSpacing.xl)
    }

    private var scoreHistoryChart: some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            Text("SCORE HISTORY")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(1)

            if historyRuns.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(Array(historyRuns.enumerated()), id: \.offset) { index, record in
                        LineMark(
                            x: .value("Session", index + 1),
                            y: .value("Score", record.score)
                        )
                        .foregroundStyle(Color.hxCyan)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Session", index + 1),
                            y: .value("Score", record.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.hxCyan.opacity(0.25), Color.hxCyan.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        // Highlight current run
                        if record.id == historyRuns.last?.id {
                            PointMark(
                                x: .value("Session", index + 1),
                                y: .value("Score", record.score)
                            )
                            .foregroundStyle(Color.hxCyan)
                            .symbolSize(80)
                        }
                    }
                }
                .chartYScale(domain: 0...max(100, (historyRuns.map(\.score).max() ?? 100) + 10))
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(Color(white: 0.15))
                        AxisValueLabel()
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(Color(white: 0.15))
                        AxisValueLabel()
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
                .frame(height: 200)
                .padding(HXSpacing.md)
                .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.md))
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: HXSpacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.largeTitle)
                    .foregroundStyle(Color.hxSurfaceBorder)
                Text("No history yet")
                    .font(.hxBody)
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(.vertical, HXSpacing.xxl)
            Spacer()
        }
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.md))
    }

    private var personalBests: some View {
        let bestScore = historyRuns.max(by: { $0.score < $1.score })?.score ?? 0
        let avgScore = historyRuns.isEmpty ? 0 : historyRuns.reduce(0) { $0 + $1.score } / historyRuns.count

        return VStack(alignment: .leading, spacing: HXSpacing.sm) {
            Text("PERSONAL BESTS")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(1)

            HStack(spacing: HXSpacing.md) {
                AnalysisStatTile(label: "Best Score", value: "\(bestScore)", color: Color.hxAmber)
                AnalysisStatTile(label: "Avg Score", value: "\(avgScore)", color: Color.hxCyan)
                AnalysisStatTile(label: "Total Runs", value: "\(historyRuns.count)", color: Color(white: 0.6))
            }
        }
    }

    private func accuracyText(_ run: RunSummaryRecord) -> String {
        if let acc = run.accuracyPercent {
            return String(format: "%.0f%%", acc)
        }
        return "—"
    }

    private func durationText(_ run: RunSummaryRecord) -> String {
        let s = run.durationMS / 1000
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m\(r)s"
    }
}

// MARK: - Details Tab

private struct DetailsTab: View {
    let run: RunSummaryRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: HXSpacing.lg) {
                if let run {
                    runDetailRows(run: run)
                } else {
                    emptyState
                }
                Spacer(minLength: HXSpacing.xl)
            }
            .padding(HXSpacing.xl)
        }
    }

    private func runDetailRows(run: RunSummaryRecord) -> some View {
        VStack(spacing: HXSpacing.sm) {
            detailRow("Task", value: TaskDefinition.all.first { $0.id.rawValue == run.taskID }?.title ?? run.taskID)
            detailRow("Mode", value: run.mode.capitalized)
            detailRow("Score", value: "\(run.score) pts")
            detailRow("Targets Hit", value: "\(run.completedTargets) of \(run.totalTargets)")
            if let acc = run.accuracyPercent {
                detailRow("Accuracy", value: String(format: "%.1f%%", acc))
            }
            detailRow("Duration", value: formattedDuration(run.durationMS))
            detailRow("HandX Used", value: run.handXUsed ? "Yes" : "No")
            detailRow("Started", value: run.startedAt.formatted(date: .abbreviated, time: .shortened))
            detailRow("Run ID", value: run.id.uuidString.prefix(8).uppercased() + "…", dim: true)
        }
    }

    private func detailRow(_ label: String, value: String, dim: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.hxBody)
                .foregroundStyle(Color(white: 0.55))
            Spacer()
            Text(value)
                .font(dim ? .hxMonoCaption : .hxBody)
                .foregroundStyle(dim ? Color(white: 0.35) : .white)
                .lineLimit(1)
        }
        .padding(.horizontal, HXSpacing.lg)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.sm))
    }

    private var emptyState: some View {
        VStack(spacing: HXSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color.hxSurfaceBorder)
            Text("Run data unavailable")
                .font(.hxBody)
                .foregroundStyle(Color(white: 0.35))
        }
        .padding(.top, 60)
    }

    private func formattedDuration(_ ms: Int) -> String {
        let s = ms / 1000
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return r == 0 ? "\(m) min" : "\(m)m \(r)s"
    }
}

// MARK: - HandX Tab

private struct HandXTab: View {
    let run: RunSummaryRecord?

    var body: some View {
        ScrollView {
            VStack(spacing: HXSpacing.lg) {
                if let run {
                    handXSummary(run: run)
                } else {
                    emptyState
                }
                Spacer(minLength: HXSpacing.xl)
            }
            .padding(HXSpacing.xl)
        }
    }

    private func handXSummary(run: RunSummaryRecord) -> some View {
        VStack(spacing: HXSpacing.md) {
            // Status badge
            HStack(spacing: HXSpacing.sm) {
                StatusDot(color: run.handXUsed ? Color.hxSuccess : Color(white: 0.4), isActive: run.handXUsed)
                Text(run.handXUsed ? "HandX Active" : "HandX Not Used")
                    .font(.hxHeadline)
                    .foregroundStyle(run.handXUsed ? Color.hxSuccess : Color(white: 0.5))
            }
            .padding(HXSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                run.handXUsed ? Color.hxSuccess.opacity(0.08) : Color.hxSurface,
                in: RoundedRectangle(cornerRadius: HXRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HXRadius.md)
                    .strokeBorder(
                        run.handXUsed ? Color.hxSuccess.opacity(0.25) : Color.hxSurfaceBorder,
                        lineWidth: 1
                    )
            )

            if run.handXUsed {
                VStack(alignment: .leading, spacing: HXSpacing.sm) {
                    Text("DEVICE INFO")
                        .font(.hxCaption)
                        .foregroundStyle(Color(white: 0.45))
                        .kerning(1)

                    handXRow("Connection", value: "BLE (HandX)")
                    handXRow("Mode", value: run.mode == "lockedSprint" ? "Locked Sprint (Required)" : "Optional")
                }
            } else {
                VStack(spacing: HXSpacing.sm) {
                    Image(systemName: "bolt.horizontal.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(white: 0.3))
                    Text("Connect a HandX device before your next run to track resistance and grip data.")
                        .font(.hxBody)
                        .foregroundStyle(Color(white: 0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, HXSpacing.xl)
            }
        }
    }

    private func handXRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.hxBody)
                .foregroundStyle(Color(white: 0.55))
            Spacer()
            Text(value)
                .font(.hxBody)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, HXSpacing.lg)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.sm))
    }

    private var emptyState: some View {
        VStack(spacing: HXSpacing.sm) {
            Image(systemName: "bolt.horizontal.slash")
                .font(.largeTitle)
                .foregroundStyle(Color.hxSurfaceBorder)
            Text("Run data unavailable")
                .font(.hxBody)
                .foregroundStyle(Color(white: 0.35))
        }
        .padding(.top, 60)
    }
}

// MARK: - Notes Tab

private struct NotesTab: View {
    let runID: UUID
    @Binding var notes: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Notes editor
            ZStack(alignment: .topLeading) {
                if notes.isEmpty && !isFocused {
                    Text("Add notes about this run — observations, what to improve, coaching cues…")
                        .font(.hxBody)
                        .foregroundStyle(Color(white: 0.30))
                        .padding(.horizontal, HXSpacing.xl + 4)
                        .padding(.top, HXSpacing.xl + 4)
                }

                TextEditor(text: $notes)
                    .font(.hxBody)
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal, HXSpacing.lg)
                    .padding(.top, HXSpacing.lg)
                    .tint(Color.hxCyan)
                    .onChange(of: notes) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "run.notes.\(runID.uuidString)")
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hxBackground)

            // Bottom hint
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.hxSuccess)
                    .font(.caption)
                Text("Notes saved automatically")
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.35))
                Spacer()
                Text("\(notes.count) chars")
                    .font(.hxMonoCaption)
                    .foregroundStyle(Color(white: 0.30))
            }
            .padding(.horizontal, HXSpacing.xl)
            .padding(.vertical, HXSpacing.md)
            .background(Color.hxSurface)
        }
    }
}

// MARK: - Shared Sub-component

private struct AnalysisStatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.hxTitle3)
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.sm))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RunSummaryRecord.self, configurations: config)
    let ctx = container.mainContext
    let id = UUID()
    let draft = RunSummaryDraft(
        runID: id,
        userID: UUID(),
        taskID: TaskIdentifier.keyLock.rawValue,
        mode: TaskMode.guided.rawValue,
        startedAt: Date(timeIntervalSinceNow: -300),
        endedAt: .now,
        durationMS: 300_000,
        score: 78,
        completedTargets: 8,
        totalTargets: 10,
        accuracyPercent: 80.0,
        handXUsed: true,
        summaryPayload: RunPayload()
    )
    ctx.insert(RunSummaryRecord(draft: draft))
    return NavigationStack {
        AnalysisView(runID: id, appModel: AppModel())
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
