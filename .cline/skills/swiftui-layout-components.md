# SwiftUI Layout & Components — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-layout-components`
**Use when:** Landscape splits, card grids, collapsible panels, custom pill layouts.

---

## Standard Screen Structure (Landscape iPad)

### TaskRunner / Camera screens
```swift
VStack(spacing: 0) {
    RunnerHUDView(...)          // 64pt fixed top strip
        .frame(height: 64)

    HStack(spacing: 0) {
        cameraContent             // .frame(maxWidth: .infinity)
        panelDivider              // 1pt Color.hxSurfaceBorder
        TrainerControlsPanel(...) // .frame(width: 320)
    }
    .frame(maxHeight: .infinity)

    bottomActionBar              // .ultraThinMaterial
}
```

### Hub / Split-panel screens
```swift
HStack(spacing: 0) {
    leftPanel                   // .frame(width: 288)
    Rectangle()
        .fill(Color.hxSurfaceBorder)
        .frame(width: 1)
    rightContent                // .frame(maxWidth: .infinity)
}
```

## Card Grid (TaskPicker)

```swift
LazyVGrid(
    columns: [GridItem(.adaptive(minimum: 300, maximum: 500))],
    spacing: HXSpacing.lg
) {
    ForEach(tasks) { task in
        TaskCard(task: task)
    }
}
```

## Custom FlowLayout (mode pills)

```swift
// Used in TaskPickerView for wrapping pill rows
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        layout(subviews: subviews, in: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = layout(subviews: subviews, in: bounds.width)
        zip(subviews, result.origins).forEach { view, origin in
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                       proposal: .unspecified)
        }
    }
    // ...full implementation in TaskPickerView.swift
}
```

## Collapsible Panel Section (TrainerControlsPanel)

```swift
private struct PanelSection<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.hxDefault) { isOpen.toggle() } } label: {
                HStack {
                    Text(title.uppercased()).font(.hxCaption).foregroundStyle(...)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                }
                .padding(.vertical, HXSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                content
                    .padding(.top, HXSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HXSpacing.md)
        .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.md))
    }
}
```

## Safe Area & Keyboard

Use `.safeAreaInset(edge: .bottom)` to pin bars above keyboard:
```swift
ScrollView { content }
    .safeAreaInset(edge: .bottom) {
        actionBar
    }
```

## Key Rules

- Use `LazyVStack` (not `VStack`) inside `ScrollView` for any list > 10 items
- Touch targets ≥ 44pt — use `.frame(minWidth: 44, minHeight: 44)` on small buttons
- Never put `GeometryReader` inside a `LazyVGrid` or `LazyVStack`
- `.contentShape(Rectangle())` on any row/card that should be tappable edge-to-edge
- `.scrollEdgeEffectStyle(.soft, for: .top)` on all main scroll views
