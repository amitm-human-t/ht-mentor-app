import SwiftUI
import UIKit

// MARK: - TaskPickerView

struct TaskPickerView: View {
    let appModel: AppModel
    @Namespace private var zoomNS
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader
            Divider().background(Color.hxSurfaceBorder)
            taskGrid
        }
        .background(Color.hxBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var pickerHeader: some View {
        HStack(spacing: HXSpacing.md) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.callout.weight(.semibold))
                    Text("Hub")
                        .font(.hxCallout)
                }
                .foregroundStyle(Color.hxCyan)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.hxSurfaceBorder)
                .frame(width: 1, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text("Tasks")
                    .font(.hxTitle2)
                    .foregroundStyle(.white)
                Text("Select a task and mode to begin")
                    .font(.hxBody)
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()
            if let reason = appModel.taskStartBlockReason {
                HStack(spacing: HXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.hxWarning)
                        .font(.callout)
                    Text(reason)
                        .font(.hxCaption)
                        .foregroundStyle(Color.hxWarning)
                        .lineLimit(2)
                        .frame(maxWidth: 280)
                }
                .padding(.horizontal, HXSpacing.md)
                .padding(.vertical, HXSpacing.sm)
                .background(Color.hxWarning.opacity(0.10), in: RoundedRectangle(cornerRadius: HXRadius.sm))
            }
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.lg)
        .background(Color.hxSurface)
    }

    // MARK: - Task Grid

    private var taskGrid: some View {
        ScrollView(showsIndicators: false) {
            GlassEffectContainer(spacing: 20) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 20)],
                    spacing: 20
                ) {
                    ForEach(TaskDefinition.all, id: \.id) { task in
                        TaskCard(
                            task: task,
                            appModel: appModel,
                            zoomNS: zoomNS
                        )
                        .matchedTransitionSource(id: task.id, in: zoomNS)
                    }
                }
                .padding(HXSpacing.xl)
            }
        }
        .background(Color.hxBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - TaskCard

private struct TaskCard: View {
    let task: TaskDefinition
    let appModel: AppModel
    let zoomNS: Namespace.ID

    private var visibleModes: [TaskMode] {
        task.supportedModes.filter { mode in
            !(mode == .lockedSprint && appModel.bleManager.connectionState != .connected)
        }
    }

    private var showsLockedSprintHint: Bool {
        task.supportedModes.contains(.lockedSprint)
            && appModel.bleManager.connectionState != .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HXSpacing.lg) {
            cardTopRow
            modePills
            if showsLockedSprintHint {
                lockedSprintHint
            }
        }
        .padding(HXSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.lg))
        .task {
            appModel.prefetchModels(for: task.id)
        }
    }

    private var cardTopRow: some View {
        HStack(alignment: .top, spacing: HXSpacing.md) {
            Image(systemName: taskIcon)
                .font(.system(size: 28))
                .foregroundStyle(taskAccent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.hxHeadline)
                    .foregroundStyle(.white)
                Text(task.subtitle)
                    .font(.hxBody)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
    }

    private var modePills: some View {
        FlowLayout(spacing: HXSpacing.sm) {
            ForEach(visibleModes, id: \.self) { mode in
                Button {
                    guard appModel.canStartTasks else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    appModel.runnerCoordinator.prepare(task: task, mode: mode)
                    appModel.startTask(task)
                } label: {
                    HStack(spacing: 5) {
                        if mode == .lockedSprint {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                        }
                        Text(mode.displayTitle)
                            .font(.hxCaption)
                    }
                    .padding(.horizontal, HXSpacing.md)
                    .padding(.vertical, HXSpacing.sm)
                    .foregroundStyle(appModel.canStartTasks ? modePillForeground(mode) : .white.opacity(0.35))
                    .background(
                        Capsule()
                            .stroke(
                                appModel.canStartTasks ? modePillBorder(mode) : Color.hxSurfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .background(
                        Capsule()
                            .fill(appModel.canStartTasks ? modePillFill(mode) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!appModel.canStartTasks)
            }
        }
    }

    private var lockedSprintHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(Color.hxAmber.opacity(0.7))
            Text("Connect HandX to unlock Locked Sprint")
                .font(.hxCaption)
                .foregroundStyle(.white.opacity(0.40))
        }
    }

    // MARK: - Style Helpers

    private var taskIcon: String {
        switch task.id {
        case .keyLock:        return "key.fill"
        case .tipPositioning: return "scope"
        case .rubberBand:     return "arrow.left.and.right"
        case .springsSuturing: return "waveform"
        case .manualScoring:  return "hand.raised.fill"
        }
    }

    private var taskAccent: Color {
        switch task.id {
        case .keyLock:        return Color.hxAmber
        case .tipPositioning: return Color.hxCyan
        case .rubberBand:     return Color.hxSuccess
        case .springsSuturing: return Color(red: 0.55, green: 0.32, blue: 0.90)
        case .manualScoring:  return Color(red: 0.95, green: 0.35, blue: 0.55)
        }
    }

    private func modePillForeground(_ mode: TaskMode) -> Color {
        switch mode {
        case .lockedSprint:  return Color.hxAmber
        case .guided:        return Color.hxCyan
        default:             return .white
        }
    }

    private func modePillBorder(_ mode: TaskMode) -> Color {
        switch mode {
        case .lockedSprint:  return Color.hxAmber.opacity(0.6)
        case .guided:        return Color.hxCyan.opacity(0.5)
        default:             return Color.hxSurfaceBorder
        }
    }

    private func modePillFill(_ mode: TaskMode) -> Color {
        switch mode {
        case .lockedSprint:  return Color.hxAmber.opacity(0.08)
        case .guided:        return Color.hxCyan.opacity(0.06)
        default:             return Color.clear
        }
    }
}

// MARK: - TaskMode displayTitle

private extension TaskMode {
    var displayTitle: String {
        switch self {
        case .guided:       return "Guided"
        case .sprint:       return "Sprint"
        case .lockedSprint: return "Locked Sprint"
        case .freestyle:    return "Freestyle"
        case .tutorial:     return "Tutorial"
        case .timer:        return "Timer"
        case .survival:     return "Survival"
        case .manual:       return "Manual"
        }
    }
}

// MARK: - FlowLayout
// Simple left-to-right wrapping layout for mode pills

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        _ = width // suppress warning
    }
}
