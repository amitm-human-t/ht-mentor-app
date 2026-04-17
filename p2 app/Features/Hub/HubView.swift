import SwiftUI

// MARK: - HubView

struct HubView: View {
    let appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: 288)

            Rectangle()
                .fill(Color.hxSurfaceBorder)
                .frame(width: 1)
                .ignoresSafeArea()

            rightContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.hxBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().background(Color.hxSurfaceBorder)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: HXSpacing.lg) {
                    userChip
                    handXWidget
                    cameraPreviewWidget
                    systemStatusWidget
                }
                .padding(HXSpacing.lg)
            }
        }
        .background(Color.hxSurface.ignoresSafeArea())
    }

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HandX")
                        .font(.hxTitle2)
                        .foregroundStyle(Color.hxCyan)
                    Text("Training Hub")
                        .font(.hxCallout)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button {
                    appModel.openBLEConsole()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.callout)
                        .foregroundStyle(Color.hxSurfaceBorder)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HXSpacing.lg)
        .padding(.top, HXSpacing.xxl)
        .padding(.bottom, HXSpacing.lg)
    }

    private var userChip: some View {
        Button {
            appModel.openUserChooser()
        } label: {
            HStack(spacing: HXSpacing.md) {
                AvatarView(
                    name: appModel.selectedUser?.displayName ?? "?",
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(appModel.selectedUser?.displayName ?? "No Trainee")
                        .font(.hxHeadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let hand = appModel.selectedUser.flatMap({
                            DominantHand(rawValue: $0.dominantHandRawValue)
                        }) {
                            Text("\(hand.rawValue.capitalized) hand")
                                .font(.hxCaption)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text("· Tap to change")
                            .font(.hxCaption)
                            .foregroundStyle(Color.hxCyan.opacity(0.8))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.hxSurfaceBorder)
            }
            .padding(HXSpacing.md)
            .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.md))
        }
        .buttonStyle(.plain)
    }

    private var handXWidget: some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            sectionLabel("HandX Device")

            HStack(spacing: HXSpacing.sm) {
                StatusDot(color: bleStatusColor, isActive: appModel.bleManager.connectionState == .connected)
                Text(appModel.bleManager.statusText)
                    .font(.hxCallout)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
                if appModel.bleManager.connectionState == .disconnected || appModel.bleManager.connectionState == .error {
                    Button("Scan") {
                        appModel.bleManager.startScan()
                    }
                    .font(.hxCaption)
                    .foregroundStyle(Color.hxCyan)
                }
            }
        }
    }

    private var bleStatusColor: Color {
        switch appModel.bleManager.connectionState {
        case .connected:                 return Color.hxSuccess
        case .scanning, .connecting:     return Color.hxAmber
        case .disconnected, .error:      return Color.hxDanger
        }
    }

    private var cameraPreviewWidget: some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            sectionLabel("Preview")
            AppPreviewStageView(appModel: appModel, showsControls: false, compact: true)
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: HXRadius.md))
        }
    }

    private var systemStatusWidget: some View {
        HStack(spacing: HXSpacing.sm) {
            Circle()
                .fill(appModel.diagnostics.isHealthy ? Color.hxSuccess : Color.hxWarning)
                .frame(width: 8, height: 8)
            Text(appModel.diagnostics.isHealthy
                 ? "System ready"
                 : "\(appModel.diagnostics.missingEntries.count) issues found")
                .font(.hxCallout)
                .foregroundStyle(.white)
            Spacer()
            if !appModel.diagnostics.isHealthy {
                Button("Fix") { appModel.openDiagnostics() }
                    .font(.hxCaption)
                    .foregroundStyle(Color.hxWarning)
            }
        }
        .padding(HXSpacing.md)
        .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.sm))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.hxCaption)
            .foregroundStyle(.white.opacity(0.40))
            .kerning(0.5)
    }

    // MARK: - Right Content

    private var rightContent: some View {
        ScrollView(showsIndicators: false) {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    // Top row: Start Task (large) + Curriculum / Leaderboards stacked
                    HStack(alignment: .top, spacing: 16) {
                        startTaskCard
                            .frame(maxWidth: .infinity)

                        VStack(spacing: 16) {
                            HubActionCard(
                                title: "Curriculum",
                                subtitle: "Structured programs",
                                icon: "list.clipboard.fill",
                                tint: Color.hxCyan,
                                action: { }   // Phase 4
                            )
                            HubActionCard(
                                title: "Leaderboards",
                                subtitle: "Top scores & rankings",
                                icon: "trophy.fill",
                                tint: Color.hxAmber,
                                action: { }   // Phase 4
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Bottom row: Reports | Analysis | User Mgmt
                    HStack(spacing: 16) {
                        HubActionCard(
                            title: "Reports",
                            subtitle: "History & trends",
                            icon: "chart.bar.xaxis.ascending",
                            tint: Color.hxSuccess,
                            action: { }   // Phase 4
                        )
                        HubActionCard(
                            title: "Analysis",
                            subtitle: "Run breakdown",
                            icon: "waveform.path.ecg",
                            tint: Color.hxCyan,
                            action: { }   // Phase 4
                        )
                        HubActionCard(
                            title: "Trainees",
                            subtitle: "Manage profiles",
                            icon: "person.2.fill",
                            tint: Color.hxAmber,
                            action: { appModel.openUserChooser() }
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(Color.hxBackground)
    }

    // MARK: - Start Task Card

    private var startTaskCard: some View {
        Button {
            if appModel.canStartTasks {
                appModel.openTaskPicker()
            } else {
                appModel.openDiagnostics()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Image(systemName: appModel.canStartTasks ? "play.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(appModel.canStartTasks ? Color.hxCyan : Color.hxWarning)
                    .padding(.bottom, HXSpacing.md)

                Text("Start Task")
                    .font(.hxTitle2)
                    .foregroundStyle(.white)

                Text(appModel.canStartTasks
                     ? "Pick a task and mode to begin your training session."
                     : appModel.taskStartBlockReason ?? "Diagnostics required before starting.")
                    .font(.hxBody)
                    .foregroundStyle(appModel.canStartTasks ? .white.opacity(0.65) : Color.hxWarning)
                    .lineLimit(3)
                    .padding(.top, 4)

                Spacer()

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right.circle")
                        .font(.title2)
                        .foregroundStyle(Color.hxCyan.opacity(appModel.canStartTasks ? 0.7 : 0.3))
                }
            }
            .padding(HXSpacing.xl)
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.hxCyan.opacity(appModel.canStartTasks ? 0.13 : 0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HubActionCard

private struct HubActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HXSpacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)

                Spacer(minLength: HXSpacing.sm)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.hxHeadline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.hxCaption)
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(2)
                }
            }
            .padding(HXSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.lg))
        }
        .buttonStyle(.plain)
    }
}
