import SwiftUI
import SwiftData
import Charts

// MARK: - ReportsView

struct ReportsView: View {
    let appModel: AppModel

    @Query(sort: \RunSummaryRecord.startedAt, order: .reverse)
    private var allRuns: [RunSummaryRecord]

    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var selectedTaskID: String? = nil
    @State private var showDatePicker = false
    @Environment(\.dismiss) private var dismiss

    // MARK: Filtered data

    private var filteredRuns: [RunSummaryRecord] {
        allRuns.filter { run in
            run.startedAt >= startDate.startOfDay &&
            run.startedAt <= endDate.endOfDay &&
            (selectedTaskID == nil || run.taskID == selectedTaskID)
        }
    }

    private var totalSessions: Int { filteredRuns.count }

    private var avgScore: Int {
        guard !filteredRuns.isEmpty else { return 0 }
        return filteredRuns.reduce(0) { $0 + $1.score } / filteredRuns.count
    }

    private var bestScore: Int {
        filteredRuns.max(by: { $0.score < $1.score })?.score ?? 0
    }

    private var totalMinutes: Int {
        filteredRuns.reduce(0) { $0 + $1.durationMS } / 60_000
    }

    private struct TaskStat: Identifiable {
        let id: String
        let name: String
        let count: Int
        let avgScore: Int
    }

    private var taskStats: [TaskStat] {
        var counts = [String: Int]()
        var scores = [String: [Int]]()
        for run in filteredRuns {
            counts[run.taskID, default: 0] += 1
            scores[run.taskID, default: []].append(run.score)
        }
        return counts.map { id, count in
            let avg = scores[id].map { $0.reduce(0, +) / $0.count } ?? 0
            let name = TaskDefinition.all.first { $0.id.rawValue == id }?.title ?? id
            return TaskStat(id: id, name: name, count: count, avgScore: avg)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.hxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: HXSpacing.xl) {
                        // Date range + task filter controls
                        controlsSection
                            .padding(.horizontal, HXSpacing.xl)
                            .padding(.top, HXSpacing.xl)

                        Divider()
                            .background(Color.hxSurfaceBorder)
                            .padding(.horizontal, HXSpacing.xl)

                        if filteredRuns.isEmpty {
                            emptyState
                        } else {
                            // Summary stat cards
                            summaryCards
                                .padding(.horizontal, HXSpacing.xl)

                            // Per-task bar chart
                            if !taskStats.isEmpty {
                                taskChart
                                    .padding(.horizontal, HXSpacing.xl)
                            }

                            // Recent runs list
                            recentRunsSection
                                .padding(.horizontal, HXSpacing.xl)
                        }

                        Spacer(minLength: HXSpacing.xxl)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                    Text("Back")
                        .font(.hxCallout)
                }
                .foregroundStyle(Color.hxCyan)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: HXSpacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("REPORTS")
                    .kerning(1.5)
            }
            .font(.hxCaption)
            .foregroundStyle(Color(white: 0.45))

            Spacer()
            Color.clear.frame(width: 60)
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: HXSpacing.md) {
            // Date range
            HStack(spacing: HXSpacing.sm) {
                Button {
                    showDatePicker = true
                } label: {
                    HStack(spacing: HXSpacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.hxCyan)
                        Text(dateRangeLabel)
                            .font(.hxBody)
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .padding(.horizontal, HXSpacing.md)
                    .padding(.vertical, HXSpacing.sm)
                    .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: HXRadius.sm)
                            .strokeBorder(Color.hxSurfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Quick range buttons
                ForEach([("7d", 7), ("30d", 30), ("90d", 90)], id: \.0) { label, days in
                    Button {
                        withAnimation(.hxDefault) {
                            endDate = .now
                            startDate = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
                        }
                    } label: {
                        Text(label)
                            .font(.hxCaption)
                            .foregroundStyle(Color(white: 0.55))
                            .padding(.horizontal, HXSpacing.sm)
                            .padding(.vertical, 6)
                            .background(Color.hxSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.hxSurfaceBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Task filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HXSpacing.sm) {
                    FilterPillSmall(label: "All Tasks", isSelected: selectedTaskID == nil) {
                        withAnimation(.hxDefault) { selectedTaskID = nil }
                    }
                    ForEach(TaskDefinition.all) { task in
                        FilterPillSmall(label: task.title, isSelected: selectedTaskID == task.id.rawValue) {
                            withAnimation(.hxDefault) {
                                selectedTaskID = (selectedTaskID == task.id.rawValue) ? nil : task.id.rawValue
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: HXSpacing.md) {
            ReportStatCard(icon: "list.bullet", label: "Sessions", value: "\(totalSessions)", color: Color.hxCyan)
            ReportStatCard(icon: "chart.bar.fill", label: "Avg Score", value: "\(avgScore)", color: Color.hxAmber)
            ReportStatCard(icon: "trophy.fill", label: "Best", value: "\(bestScore)", color: Color(red: 1.0, green: 0.84, blue: 0.0))
            ReportStatCard(icon: "clock.fill", label: "Time", value: totalTimeText, color: Color(white: 0.6))
        }
    }

    private var totalTimeText: String {
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    // MARK: - Task Chart

    private var taskChart: some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            Text("SESSIONS BY TASK")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(1)

            Chart(taskStats) { stat in
                BarMark(
                    x: .value("Task", stat.name),
                    y: .value("Sessions", stat.count)
                )
                .foregroundStyle(Color.hxCyan.gradient)
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    Text("\(stat.count)")
                        .font(.hxCaption)
                        .foregroundStyle(Color.hxCyan)
                }
            }
            .chartYScale(domain: 0...(max(1, (taskStats.map(\.count).max() ?? 1)) + 1))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color(white: 0.12))
                    AxisValueLabel().foregroundStyle(Color(white: 0.4))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .frame(height: 180)
            .padding(HXSpacing.md)
            .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.md))
        }
    }

    // MARK: - Recent Runs

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            HStack {
                Text("RECENT RUNS")
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.45))
                    .kerning(1)
                Spacer()
                Text("\(filteredRuns.count) total")
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.35))
            }

            LazyVStack(spacing: HXSpacing.xs) {
                ForEach(Array(filteredRuns.prefix(20))) { run in
                    RecentRunRow(run: run)
                }
                if filteredRuns.count > 20 {
                    Text("+ \(filteredRuns.count - 20) more runs")
                        .font(.hxCaption)
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.top, HXSpacing.sm)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: HXSpacing.md) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 52))
                .foregroundStyle(Color.hxSurfaceBorder)
                .padding(.top, HXSpacing.xxl)
            VStack(spacing: HXSpacing.sm) {
                Text("No Runs in Range")
                    .font(.hxTitle3)
                    .foregroundStyle(.white)
                Text("Adjust the date range or task filter to see run data.")
                    .font(.hxBody)
                    .foregroundStyle(Color(white: 0.40))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, HXSpacing.xxl)
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: HXSpacing.xl) {
                VStack(alignment: .leading, spacing: HXSpacing.sm) {
                    Text("START DATE")
                        .font(.hxCaption)
                        .foregroundStyle(Color(white: 0.45))
                        .kerning(1)
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(Color.hxCyan)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: HXSpacing.sm) {
                    Text("END DATE")
                        .font(.hxCaption)
                        .foregroundStyle(Color(white: 0.45))
                        .kerning(1)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(Color.hxCyan)
                        .labelsHidden()
                }

                Spacer()
            }
            .padding(HXSpacing.xxl)
            .background(Color.hxBackground.ignoresSafeArea())
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                        .tint(Color.hxCyan)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: startDate)) – \(fmt.string(from: endDate))"
    }
}

// MARK: - Report Stat Card

private struct ReportStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: HXSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.hxTitle3)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.md))
    }
}

// MARK: - Recent Run Row

private struct RecentRunRow: View {
    let run: RunSummaryRecord

    private var taskTitle: String {
        TaskDefinition.all.first { $0.id.rawValue == run.taskID }?.title ?? run.taskID
    }

    var body: some View {
        HStack(spacing: HXSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taskTitle)
                    .font(.hxBody)
                    .foregroundStyle(.white)
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.40))
            }

            Spacer()

            Text("\(run.score)")
                .font(.hxMono(16, weight: .semibold))
                .foregroundStyle(.white)

            Text(run.mode.capitalized)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, HXSpacing.md)
        .padding(.vertical, HXSpacing.sm)
        .background(Color.hxSurface, in: RoundedRectangle(cornerRadius: HXRadius.sm))
    }
}

// MARK: - Small Filter Pill

private struct FilterPillSmall: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.hxCaption)
                .foregroundStyle(isSelected ? .white : Color(white: 0.55))
                .padding(.horizontal, HXSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.hxCyan.opacity(0.20) : Color.hxSurface,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(
                    isSelected ? Color.hxCyan.opacity(0.45) : Color.hxSurfaceBorder,
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
        .animation(.hxDefault, value: isSelected)
    }
}

// MARK: - Date Helpers

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    var endOfDay: Date {
        Calendar.current.date(byAdding: .init(hour: 23, minute: 59, second: 59), to: startOfDay) ?? self
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RunSummaryRecord.self, configurations: config)
    let ctx = container.mainContext
    let uid = UUID()
    let tasks: [(String, String)] = [
        ("keyLock", "guided"), ("keyLock", "sprint"), ("tipPositioning", "guided"),
        ("rubberBand", "sprint"), ("keyLock", "guided"), ("springsSuturing", "guided")
    ]
    for (i, (task, mode)) in tasks.enumerated() {
        let draft = RunSummaryDraft(
            runID: UUID(), userID: uid, taskID: task, mode: mode,
            startedAt: Date(timeIntervalSinceNow: -Double(i) * 86400),
            endedAt: .now, durationMS: 120_000 + i * 10_000,
            score: 60 + i * 5, completedTargets: 7 + i % 3, totalTargets: 10,
            accuracyPercent: Double(65 + i * 4), handXUsed: i % 2 == 0, summaryPayload: RunPayload()
        )
        ctx.insert(RunSummaryRecord(draft: draft))
    }
    return NavigationStack {
        ReportsView(appModel: AppModel())
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
