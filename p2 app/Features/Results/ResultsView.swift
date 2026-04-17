import SwiftUI

// MARK: - ResultsView

struct ResultsView: View {
    let summary: RunSummaryDraft
    let appModel: AppModel

    @State private var displayedScore = 0
    @State private var cardsVisible = false

    var body: some View {
        ZStack {
            Color.hxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                ScrollView {
                    VStack(spacing: HXSpacing.xxl) {
                        Spacer(minLength: HXSpacing.xl)

                        // Hero score section
                        heroSection
                            .padding(.horizontal, HXSpacing.xxl)

                        // Stat cards
                        statCards
                            .padding(.horizontal, HXSpacing.xxl)
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)

                        Spacer(minLength: HXSpacing.xl)

                        // CTA row
                        ctaSection
                            .padding(.horizontal, HXSpacing.xxl)
                            .opacity(cardsVisible ? 1 : 0)

                        Spacer(minLength: HXSpacing.xxl)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Stagger: score counts first, then cards fade in
            withAnimation(.spring(duration: 1.0, bounce: 0.25).delay(0.15)) {
                displayedScore = summary.score
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5)) {
                cardsVisible = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                appModel.path.removeLast()
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

            Text("RUN COMPLETE")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(1.5)

            Spacer()

            // Balance
            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.md)
        .background(Color.hxSurface)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: HXSpacing.sm) {
            // Task + mode badge row
            HStack(spacing: HXSpacing.sm) {
                Text(summary.taskTitle.uppercased())
                    .font(.hxCaption)
                    .foregroundStyle(Color.hxCyan)
                    .kerning(1.5)

                Text("·")
                    .foregroundStyle(Color(white: 0.35))

                Text(modeLabel(summary.mode))
                    .font(.hxCaption)
                    .foregroundStyle(Color(white: 0.5))
                    .kerning(0.5)
            }

            // Animated score number
            Text("\(displayedScore)")
                .font(.system(size: 92, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy, value: displayedScore)
                .monospacedDigit()

            Text("SCORE")
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
                .kerning(2)

            // Grade pill
            gradePill
                .padding(.top, HXSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private var gradePill: some View {
        let (label, color) = gradeInfo(score: summary.score)
        return Text(label)
            .font(.hxCallout)
            .foregroundStyle(color)
            .padding(.horizontal, HXSpacing.lg)
            .padding(.vertical, HXSpacing.xs)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Stat Cards

    private var statCards: some View {
        HStack(spacing: HXSpacing.md) {
            ResultStatCard(
                icon: "clock.fill",
                value: durationText,
                label: "Duration",
                color: Color.hxCyan
            )
            ResultStatCard(
                icon: "scope",
                value: accuracyText,
                label: "Accuracy",
                color: Color.hxSuccess
            )
            ResultStatCard(
                icon: "target",
                value: "\(summary.completedTargets)/\(summary.totalTargets)",
                label: "Targets",
                color: Color.hxAmber
            )
        }
    }

    // MARK: - CTAs

    private var ctaSection: some View {
        VStack(spacing: HXSpacing.sm) {
            // Primary: Analyze
            Button {
                appModel.openAnalysis(runID: summary.runID)
            } label: {
                Label("Analyze Run", systemImage: "waveform.path.ecg")
                    .font(.hxHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.hxCyan)

            // Secondary row: Retry + Hub
            HStack(spacing: HXSpacing.sm) {
                Button {
                    // Go back to TaskRunner — user taps Retry there
                    appModel.path.removeLast()
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.hxBody)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    appModel.path.removeAll()
                } label: {
                    Label("Hub", systemImage: "house.fill")
                        .font(.hxBody)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            // Tertiary: Leaderboards link
            Button {
                appModel.openLeaderboards()
            } label: {
                HStack(spacing: HXSpacing.xs) {
                    Image(systemName: "trophy.fill")
                    Text("View Leaderboards")
                }
                .font(.hxCallout)
                .foregroundStyle(Color.hxAmber)
            }
            .buttonStyle(.plain)
            .padding(.top, HXSpacing.xs)
        }
    }

    // MARK: - Helpers

    private var durationText: String {
        let s = summary.durationSeconds
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let rem = s % 60
        return rem == 0 ? "\(m)m" : "\(m)m \(rem)s"
    }

    private var accuracyText: String {
        if let acc = summary.accuracyPercent {
            return String(format: "%.0f%%", acc)
        }
        return "—"
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "guided":        return "Guided"
        case "sprint":        return "Sprint"
        case "lockedSprint":  return "Locked Sprint"
        case "freestyle":     return "Freestyle"
        case "tutorial":      return "Tutorial"
        case "timer":         return "Timer"
        case "survival":      return "Survival"
        case "manual":        return "Manual"
        default:              return mode.capitalized
        }
    }

    private func gradeInfo(score: Int) -> (String, Color) {
        switch score {
        case 90...:   return ("Excellent", Color.hxSuccess)
        case 75..<90: return ("Great", Color.hxCyan)
        case 55..<75: return ("Good", Color.hxAmber)
        case 30..<55: return ("Fair", Color.hxWarning)
        default:      return ("Keep Practicing", Color(white: 0.5))
        }
    }
}

// MARK: - Stat Card Component

private struct ResultStatCard: View {
    let icon: String
    let value: String
    let label: String
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

            Text(label.uppercased())
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.40))
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HXSpacing.lg)
        .glassCard(padding: 0)
    }
}

// MARK: - Preview

#Preview {
    let draft = RunSummaryDraft(
        runID: UUID(),
        userID: UUID(),
        taskID: TaskIdentifier.keyLock.rawValue,
        mode: TaskMode.guided.rawValue,
        startedAt: Date(timeIntervalSinceNow: -125),
        endedAt: .now,
        durationMS: 125_000,
        score: 84,
        completedTargets: 9,
        totalTargets: 10,
        accuracyPercent: 91.2,
        handXUsed: true,
        summaryPayload: [:]
    )
    return NavigationStack {
        ResultsView(summary: draft, appModel: AppModel())
    }
    .preferredColorScheme(.dark)
}
