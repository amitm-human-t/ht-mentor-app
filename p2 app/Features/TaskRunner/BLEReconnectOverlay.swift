import SwiftUI

/// Full-screen overlay shown when HandX disconnects during a Locked Sprint run.
/// Displays a countdown ring, reconnect status, and an escape button.
/// Dismissed automatically when `disconnectCountdown` becomes nil.
struct BLEReconnectOverlay: View {
    let countdown: Int          // 0–10
    let onEndRun: () -> Void

    private let totalSeconds = 10

    var body: some View {
        ZStack {
            // Backdrop
            Rectangle()
                .fill(.black.opacity(0.72))
                .ignoresSafeArea()

            VStack(spacing: 36) {
                // Countdown ring
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.hxSurfaceBorder, lineWidth: 6)
                        .frame(width: 160, height: 160)

                    // Progress arc — animates each second
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            countdown > 3 ? Color.hxAmber : Color.hxDanger,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: countdown)

                    // Number
                    Text("\(countdown)")
                        .font(.hxDisplay)
                        .foregroundStyle(countdown > 3 ? Color.hxAmber : Color.hxDanger)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: countdown)
                }

                // Labels
                VStack(spacing: 10) {
                    Text("HandX Disconnected")
                        .font(.hxTitle2)
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.hxAmber)
                            .scaleEffect(0.85)
                        Text("Reconnecting…")
                            .font(.hxBody)
                            .foregroundStyle(Color.hxAmber)
                    }

                    Text("Run paused. Reconnect within \(countdown)s or the run will end.")
                        .font(.hxCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Escape
                Button(action: onEndRun) {
                    Label("End Run", systemImage: "xmark.circle.fill")
                        .font(.hxHeadline)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxDanger)
            }
            .padding(40)
        }
        .transition(.opacity.combined(with: .scale(0.96)))
    }

    private var progress: CGFloat {
        CGFloat(countdown) / CGFloat(totalSeconds)
    }
}

// MARK: - Preview

#Preview {
    BLEReconnectOverlay(countdown: 7) {}
        .preferredColorScheme(.dark)
}
