import SwiftUI
import SwiftData

// MARK: - LeaderboardsView

struct LeaderboardsView: View {
    let appModel: AppModel

    @Query(sort: \RunSummaryRecord.score, order: .reverse)
    private var allRuns: [RunSummaryRecord]

    @State private var selectedTaskID: String? = nil
    @State private var selectedMode: String? = nil
    @Environment(\.dismiss) private var dismiss

    // MARK: Filtered data

    private var filteredRuns: [RunSummaryRecord] {
        allRuns.filter { run in
            (selectedTaskID == nil || run.taskID == selectedTaskID) &&
            (selectedMode == nil || run.mode == selectedMode)
        }
    }

    private var topThree: [RunSummaryRecord] {
        Array(filteredRuns.prefix(3))
    }

    private var belowPodium: [RunSummaryRecord] {
        guard filteredRuns.count > 3 else { return [] }
        return Array(filteredRuns.dropFirst(3))
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.hxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                // Filter pills
                filterBar
                    .padding(.vertical, HXSpacing.sm)

                Divider().background(Color.hxSurfaceBorder)

                if filteredRuns.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: HXSpacing.xl) {
                            // Podium
                            podiumSection
                                .padding(.horizontal, HXSpacing.xl)
                                .padding(.top, HXSpacing.xl)

                            // Rows 4+
                            if !belowPodium.isEmpty {
                                rankingRows
                                    .padding(.horizontal, HXSpacing.xl)
                            }

                            Spacer(minLength: HXSpacing.xxl)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
                    Text("Back")
                        .font(.hxCallout)
                }
                .foregroundStyle(Color.hxCyan)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: HXSpacing.sm) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.hxAmber)
                Text("LEADERBOARDS")
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HXSpacing.sm) {
                // Task filters
                FilterPill(label: "All Tasks", isSelected: selectedTaskID == nil) {
                    withAnimation(.hxDefault) { selectedTaskID = nil }
                }
                ForEach(TaskDefinition.all) { task in
                    FilterPill(label: task.title, isSelected: selectedTaskID == task.id.rawValue) {
                        withAnimation(.hxDefault) {
                            selectedTaskID = (selectedTaskID == task.id.rawValue) ? nil : task.id.rawValue
                        }
                    }
                }

                Divider()
                    .frame(height: 20)
                    .background(Color.hxSurfaceBorder)
                    .padding(.horizontal, HXSpacing.xs)

                // Mode filters
                FilterPill(label: "All Modes", isSelected: selectedMode == nil) {
                    withAnimation(.hxDefault) { selectedMode = nil }
                }
                ForEach(["guided", "sprint", "lockedSprint"], id: \.self) { mode in
                    FilterPill(label: modeName(mode), isSelected: selectedMode == mode) {
                        withAnimation(.hxDefault) {
                            selectedMode = (selectedMode == mode) ? nil : mode
                        }
                    }
                }
            }
            .padding(.horizontal, HXSpacing.xl)
        }
    }

    // MARK: - Podium

    private var podiumSection: some View {
        VStack(spacing: HXSpacing.xl) {
            Text("\(filteredRuns.count) RUNS RANKED")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
                .kerning(1)

            if topThree.count >= 3 {
                // Full 3-slot podium — 2nd | 1st | 3rd
                HStack(alignment: .bottom, spacing: HXSpacing.md) {
                    PodiumSlot(rank: 2, run: topThree[1], height: 88)
                    PodiumSlot(rank: 1, run: topThree[0], height: 120)
                    PodiumSlot(rank: 3, run: topThree[2], height: 66)
                }
            } else {
                // Single-column for fewer entries
                VStack(spacing: HXSpacing.sm) {
                    ForEach(Array(topThree.enumerated()), id: \.offset) { index, run in
                        LeaderboardRow(rank: index + 1, run: run, isTop: index == 0)
                    }
                }
            }
        }
    }

    // MARK: - Ranking Rows (4+)

    private var rankingRows: some View {
        VStack(spacing: HXSpacing.sm) {
            HStack {
                Text("RANK")
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.35))
                    .frame(width: 44, alignment: .center)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, HXSpacing.md)

            LazyVStack(spacing: HXSpacing.xs) {
                ForEach(Array(belowPodium.enumerated()), id: \.element.id) { index, run in
                    LeaderboardRow(rank: index + 4, run: run, isTop: false)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Runs Yet", systemImage: "trophy")
        } description: {
            Text("Complete a task to appear on the leaderboard.")
        }
        .foregroundStyle(Color(white: 0.45))
    }

    // MARK: - Helpers

    private func modeName(_ mode: String) -> String {
        switch mode {
        case "guided":       return "Guided"
        case "sprint":       return "Sprint"
        case "lockedSprint": return "Locked"
        default:             return mode.capitalized
        }
    }
}

// MARK: - Podium Slot

private struct PodiumSlot: View {
    let rank: Int
    let run: RunSummaryRecord
    let height: CGFloat

    private var medalColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)  // gold
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.78) // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20) // bronze
        default: return Color(white: 0.45)
        }
    }

    private var taskTitle: String {
        TaskDefinition.all.first { $0.id.rawValue == run.taskID }?.title ?? run.taskID
    }

    var body: some View {
        VStack(spacing: HXSpacing.sm) {
            // Medal
            ZStack {
                Circle()
                    .fill(medalColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text("\(rank)")
                    .font(.hxTitle3)
                    .foregroundStyle(medalColor)
            }
            .overlay(
                Circle()
                    .strokeBorder(medalColor.opacity(0.40), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
            )

            // Score
            Text("\(run.score)")
                .font(.hxTitle2)
                .foregroundStyle(.white)

            // Task label
            Text(taskTitle)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Pedestal
            Rectangle()
                .fill(medalColor.opacity(0.10))
                .frame(height: height)
                .overlay(
                    Rectangle()
                        .strokeBorder(medalColor.opacity(0.20), lineWidth: 1)
                )
                .cornerRadius(4, corners: [.topLeft, .topRight])
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - LeaderboardRow

private struct LeaderboardRow: View {
    let rank: Int
    let run: RunSummaryRecord
    let isTop: Bool

    private var taskTitle: String {
        TaskDefinition.all.first { $0.id.rawValue == run.taskID }?.title ?? run.taskID
    }

    var body: some View {
        HStack(spacing: HXSpacing.md) {
            // Rank number
            Text("\(rank)")
                .font(.hxMonoBody)
                .foregroundStyle(isTop ? Color.hxAmber : Color(white: 0.40))
                .frame(width: 32, alignment: .center)

            // Task dot
            Circle()
                .fill(Color.hxCyan.opacity(0.6))
                .frame(width: 8, height: 8)

            // Task + mode
            VStack(alignment: .leading, spacing: 2) {
                Text(taskTitle)
                    .font(.hxBody)
                    .foregroundStyle(.white)
                Text(run.mode.capitalized + " · " + run.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.40))
            }

            Spacer()

            // Score
            Text("\(run.score)")
                .font(.hxMono(18, weight: .semibold))
                .foregroundStyle(.white)

            // Accuracy if present
            if let acc = run.accuracyPercent {
                Text(String(format: "%.0f%%", acc))
                    .font(.hxCaption)
                    .foregroundStyle(Color.hxSuccess)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, HXSpacing.md)
        .padding(.vertical, HXSpacing.sm)
        .background(
            isTop ? Color.hxAmber.opacity(0.05) : Color.hxSurface,
            in: RoundedRectangle(cornerRadius: HXRadius.sm)
        )
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.hxCallout)
                .foregroundStyle(isSelected ? .white : Color(white: 0.55))
                .padding(.horizontal, HXSpacing.md)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.hxCyan.opacity(0.20) : Color.hxSurface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.hxCyan.opacity(0.45) : Color.hxSurfaceBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.hxDefault, value: isSelected)
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RunSummaryRecord.self, configurations: config)
    let ctx = container.mainContext
    let uid = UUID()
    [(92, "keyLock", "sprint"),
     (85, "tipPositioning", "guided"),
     (78, "keyLock", "guided"),
     (71, "rubberBand", "sprint"),
     (65, "keyLock", "guided"),
     (58, "springsSuturing", "guided")].forEach { score, task, mode in
        let draft = RunSummaryDraft(
            runID: UUID(), userID: uid, taskID: task, mode: mode,
            startedAt: Date(timeIntervalSinceNow: -Double.random(in: 3600...86400)),
            endedAt: .now, durationMS: 120_000, score: score,
            completedTargets: score / 10, totalTargets: 10,
            accuracyPercent: Double(score), handXUsed: true, summaryPayload: RunPayload()
        )
        ctx.insert(RunSummaryRecord(draft: draft))
    }
    return NavigationStack {
        LeaderboardsView(appModel: AppModel())
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
