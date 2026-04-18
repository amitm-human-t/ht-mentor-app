import SwiftUI

/// Compact top strip displayed during an active run.
/// Shows score, progress ring, elapsed timer, BLE status, and mode badge.
/// Re-renders on every `latestOutput` change (~100ms tick) but only reads
/// the small subset of coordinator state it needs.
struct RunnerHUDView: View {
    let coordinator: RunnerCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: HXSpacing.xl) {
                scoreSection
                Divider()
                    .frame(height: 36)
                    .background(Color.hxSurfaceBorder)
                progressSection
                Divider()
                    .frame(height: 36)
                    .background(Color.hxSurfaceBorder)
                timerSection(at: context.date)
                Spacer()
                bleStatusSection
                modeBadge
            }
            .padding(.horizontal, HXSpacing.xl)
            .frame(height: 64)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SCORE")
                .font(.hxCaption)
                .foregroundStyle(.white.opacity(0.40))
            Text("\(coordinator.latestOutput.score)")
                .font(.hxMonoDisplay)
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy, value: coordinator.latestOutput.score)
        }
    }

    // MARK: - Progress Ring

    private var progressSection: some View {
        HStack(spacing: HXSpacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.hxSurfaceBorder, lineWidth: 3)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: progress)
                Text("\(coordinator.latestOutput.progress.completed)")
                    .font(Font.hxMono(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.snappy, value: coordinator.latestOutput.progress.completed)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("TARGET")
                    .font(.hxCaption)
                    .foregroundStyle(.white.opacity(0.40))
                Text(coordinator.latestOutput.targetInfo)
                    .font(.hxCallout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Timer

    private func timerSection(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TIME")
                .font(.hxCaption)
                .foregroundStyle(.white.opacity(0.40))
            Text(elapsedString(at: date))
                .font(.hxMonoBody)
                .monospacedDigit()
                .foregroundStyle(isNearCompletion ? Color.hxAmber : .white)
                .animation(.hxDefault, value: isNearCompletion)
        }
    }

    // MARK: - BLE Status

    private var bleStatusSection: some View {
        HStack(spacing: 6) {
            StatusDot(
                color: coordinator.bleConnected ? Color.hxSuccess : Color.hxDanger,
                isActive: coordinator.bleConnected
            )
            Text(coordinator.bleConnected ? "HandX" : "No HandX")
                .font(.hxCaption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Mode Badge

    private var modeBadge: some View {
        HStack(spacing: 4) {
            if coordinator.selectedMode == .lockedSprint {
                Image(systemName: "lock.fill")
                    .font(.caption2)
            }
            Text(coordinator.selectedMode.rawValue.capitalized)
                .font(.hxCaption)
        }
        .foregroundStyle(Color.hxCyan)
        .padding(.horizontal, HXSpacing.sm)
        .padding(.vertical, 4)
        .background(Color.hxCyan.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Color.hxCyan.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Helpers

    private var progress: CGFloat {
        let total = coordinator.latestOutput.progress.total
        guard total > 0 else { return 0 }
        return min(1, CGFloat(coordinator.latestOutput.progress.completed) / CGFloat(total))
    }

    private var progressColor: Color {
        switch progress {
        case ..<0.5:   return Color.hxCyan
        case ..<0.85:  return Color.hxSuccess
        default:       return Color.hxAmber
        }
    }

    private var isNearCompletion: Bool {
        progress > 0.80 && coordinator.latestOutput.progress.total > 0
    }

    private func elapsedString(at date: Date) -> String {
        let phase = coordinator.stateMachine.phase
        guard let start = coordinator.taskStartDate,
              phase == .running || phase == .paused
        else { return "--:--" }
        let elapsed = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        RunnerHUDView(coordinator: {
            let c = RunnerCoordinator(
                cameraService: CameraService(),
                debugVideoFrameSource: DebugVideoFrameSource(),
                bleManager: MockHandXBLEManager(),
                modelRegistry: CoreMLModelRegistry(),
                permissionCenter: PermissionCenter(),
                frameBus: CameraFrameBus(),
                thermalMonitor: ThermalMonitor()
            )
            c.prepare(task: TaskDefinition.all[0], mode: .guided)
            return c
        }())
        Spacer()
    }
    .background(Color.hxBackground)
    .preferredColorScheme(.dark)
}
