import SwiftUI

// MARK: - Glass Card Modifier
// Wraps content in Liquid Glass (iOS 26+). No fallback needed — iOS 26 is the deployment target.

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Apply the standard glass card treatment — Liquid Glass on iOS 26+.
    func glassCard(
        cornerRadius: CGFloat = HXRadius.lg,
        padding: CGFloat = HXSpacing.lg
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Interactive Glass Card

struct InteractiveGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Interactive glass — for tappable cards that respond to press state.
    func interactiveGlassCard(cornerRadius: CGFloat = HXRadius.lg) -> some View {
        modifier(InteractiveGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - HUD Glass Strip

/// Thin glass strip for status bars, HUD overlays, and score panels.
struct HUDGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, HXSpacing.lg)
            .padding(.vertical, HXSpacing.md)
            .glassEffect(in: Capsule())
    }
}

extension View {
    func hudGlass() -> some View {
        modifier(HUDGlassModifier())
    }
}

// MARK: - Status Dot

/// Pulsing status dot — for BLE connection, camera, etc.
struct StatusDot: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        if isActive {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.8), radius: 5)
                .phaseAnimator([0.55, 1.0]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 1.0)
                }
        } else {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 10, height: 10)
        }
    }
}
