# SwiftUI Liquid Glass — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-liquid-glass`
**Use when:** Any card surface, floating button, HUD element, control panel. This is the primary visual language.

---

## Core APIs Used in This Project

```swift
// Standard card (non-interactive)
view
    .padding(HXSpacing.lg)
    .glassEffect(.regular, in: .rect(cornerRadius: HXRadius.md))

// Interactive card (buttons, tappable cells)
view
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.md))

// Standard buttons (use these everywhere)
Button("Start") { }
    .buttonStyle(.glass)

Button("Start") { }
    .buttonStyle(.glassProminent)
    .tint(Color.hxCyan)

// Group sibling glass elements (required for morphing + blending)
GlassEffectContainer(spacing: 16) {
    // all .glassEffect() views go here
}
```

Always add iOS 17 fallback:
```swift
if #available(iOS 26, *) {
    view.glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.md))
} else {
    view.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: HXRadius.md))
}
```

## Design Token Integration

Use design tokens — never hardcode corner radii or spacing:

```swift
HXRadius.sm   // 8
HXRadius.md   // 12
HXRadius.lg   // 16
HXRadius.xl   // 24

HXSpacing.sm  // 6
HXSpacing.md  // 10
HXSpacing.lg  // 16
HXSpacing.xl  // 24
```

## GlassCard Modifiers (Core/DesignSystem/GlassCard.swift)

```swift
.glassCard()             // standard raised card
.interactiveGlassCard()  // tappable, press feedback
.hudGlass()              // capsule HUD chip

StatusDot(color: Color.hxSuccess, isActive: true)  // animated dot
```

## Layout Rules

1. Apply `.glassEffect()` **after** all layout modifiers (padding, frame)
2. Never nest `GlassEffectContainer` inside another
3. Only use `.interactive()` on tappable elements
4. Wrap all sibling glass views in one `GlassEffectContainer`

## Morphing Transitions

```swift
@Namespace private var ns

GlassEffectContainer(spacing: 24) {
    // Use glassEffectID for elements that animate in/out
    if showDetail {
        DetailView()
            .glassEffect()
            .glassEffectID("detail", in: ns)
    }
    SummaryView()
        .glassEffect()
        .glassEffectID("summary", in: ns)
}
```

## Hub + TaskPicker Patterns Used

```swift
// Hub action card (non-interactive background, interactive overlay)
VStack { ... }
    .padding(HXSpacing.xl)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: HXRadius.lg))

// Start Task hero card (tall, gradient tint)
VStack { ... }
    .glassEffect(
        .regular.tint(Color.hxCyan.opacity(0.15)).interactive(),
        in: .rect(cornerRadius: HXRadius.xl)
    )
```
