import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary surgical accent — electric cyan
    static let hxCyan     = Color(red: 0.0,  green: 0.85, blue: 0.95)
    // HandX device status indicator — amber
    static let hxAmber    = Color(red: 1.0,  green: 0.75, blue: 0.0)
    // Success / target reached — emerald
    static let hxSuccess  = Color(red: 0.15, green: 0.90, blue: 0.40)
    // Failure / drop / error — signal red
    static let hxDanger   = Color(red: 1.0,  green: 0.25, blue: 0.25)
    // Mid-run caution — warm amber
    static let hxWarning  = Color(red: 1.0,  green: 0.65, blue: 0.0)
    // Score / headline emphasis — full white
    static let hxScore    = Color.white

    // Surface tokens — OLED-optimised dark hierarchy
    static let hxBackground      = Color(white: 0.04)
    static let hxSurface         = Color(white: 0.09)
    static let hxSurfaceRaised   = Color(white: 0.14)
    static let hxSurfaceBorder   = Color(white: 0.22)
}

// MARK: - Typography

extension Font {
    // SF Pro Rounded — hero numbers, UI labels, headings
    static func hx(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // Named scale
    static let hxDisplay   = Font.hx(52, weight: .bold)
    static let hxTitle1    = Font.hx(32, weight: .bold)
    static let hxTitle2    = Font.hx(24, weight: .semibold)
    static let hxTitle3    = Font.hx(20, weight: .semibold)
    static let hxHeadline  = Font.hx(17, weight: .semibold)
    static let hxBody      = Font.hx(15)
    static let hxCallout   = Font.hx(14, weight: .medium)
    static let hxCaption   = Font.hx(12)

    // SF Mono — numeric telemetry and data readouts
    static func hxMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let hxMonoDisplay = Font.hxMono(48, weight: .bold)
    static let hxMonoBody    = Font.hxMono(14)
    static let hxMonoCaption = Font.hxMono(12)
}

// MARK: - Corner Radius

enum HXRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Spacing

enum HXSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Animation

extension Animation {
    // Standard UI response — snappy spring for taps and toggles
    static let hxDefault = Animation.spring(response: 0.30, dampingFraction: 0.74)
    // Bounce-in for score ticks and target reveals
    static let hxBounce  = Animation.spring(response: 0.40, dampingFraction: 0.62)
    // Smooth exit / dismiss
    static let hxDismiss = Animation.spring(response: 0.22, dampingFraction: 0.90)
    // Slower for modals and overlays
    static let hxModal   = Animation.spring(response: 0.48, dampingFraction: 0.80)
    // Panel slide in/out
    static let hxPanel   = Animation.spring(response: 0.36, dampingFraction: 0.82)
}
