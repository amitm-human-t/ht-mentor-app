# UI/UX Pro Max — HandX Project Reference

**Plugin:** `ui-ux-pro-max:ui-ux-pro-max`
**Use when:** Design decisions — color palette, typography, spacing, layout hierarchy, animations, accessibility.

---

## Design Language: Dark Clinical Precision

**Style:** Dark, OLED-black, premium surgical suite aesthetic.
**NOT:** Consumer app, flat pastel, or playful. Think high-end fitness tracker meets operating room.

---

## Color System (OLED Dark)

```swift
// Backgrounds (pure dark to reduced-surface dark)
Color.hxBackground      // #020617  OLED black
Color.hxSurface         // #0E1223  raised surface
Color.hxSurfaceRaised   // #1A2235  more raised
Color.hxSurfaceBorder   // #334155  subtle borders

// Accents (cool + clinical)
Color.hxCyan            // primary — electric teal (#0891B2)
Color.hxSuccess         // target hit, positive (#22C55E)
Color.hxAmber           // HandX device, caution (#F59E0B)
Color.hxDanger          // failure, drop, error (#EF4444)
Color.hxWarning         // non-critical warning (#F59E0B)

// Text
// Primary: .white or near-white
// Secondary: .white.opacity(0.55)
// Tertiary / labels: .white.opacity(0.40)
```

**Color use rules:**
- Never convey status by color alone — always pair with icon or text
- Error = hxDanger + exclamationmark.triangle.fill
- Success = hxSuccess + checkmark.circle.fill
- Device connected = hxSuccess + StatusDot
- Device disconnected = hxDanger + StatusDot (inactive)

---

## Typography Scale

```swift
Font.hxDisplay     // Hero scores: 52pt bold rounded
Font.hxTitle1      // Screen titles: 32pt bold rounded
Font.hxTitle2      // Section headers: 24pt semibold rounded
Font.hxTitle3      // Panel headers: 20pt semibold rounded
Font.hxHeadline    // Card titles: 17pt semibold rounded
Font.hxBody        // General text: 15pt regular rounded
Font.hxCallout     // Supporting text: 13pt medium
Font.hxCaption     // Labels, tags: 11pt medium
Font.hxMonoDisplay // Score counter: 48pt bold mono (stable width)
Font.hxMonoBody    // Telemetry values: 14pt regular mono
Font.hxMonoCaption // Debug values: 11pt regular mono
```

**Rules:**
- All numbers that change frequently (score, timer, BLE values) → mono font
- Card titles → `.hxHeadline`
- Secondary/descriptive text → `.hxBody` with `.white.opacity(0.75)`
- Labels and section caps → `.hxCaption` with letter-spacing `.kerning(0.5)`

---

## Spacing Scale

```swift
HXSpacing.xs  // 4pt
HXSpacing.sm  // 8pt
HXSpacing.md  // 12pt
HXSpacing.lg  // 16pt
HXSpacing.xl  // 24pt
HXSpacing.xxl // 32pt
```

**Rule:** Always use tokens, never hard-code `padding(12)`.

---

## Touch Targets

- Minimum: 44×44pt for all tappable elements
- Trainer action buttons in panel: 56pt height minimum
- Extend hit area with `.contentShape(Rectangle())` when visual is smaller
- Bottom bar buttons: full-height tappable with generous horizontal padding

---

## Hierarchy Principles

1. **One primary action per screen** — highlighted with `.glassProminent` + tint
2. **Secondary actions** — `.glass` style, visually subordinate
3. **Destructive actions** — `.tint(.hxDanger)`, placed last in row/group
4. **Labels** — ALL-CAPS + `kerning(0.5)` for section headers

---

## Animation Rules

- All state transitions use spring physics: `.animation(.hxPanel, value: ...)` or `.animation(.hxDefault, value: ...)`
- Numbers/counters use `.contentTransition(.numericText(countsDown: false))`
- Panel slide: `.transition(.move(edge: .trailing).combined(with: .opacity))`
- Modal appear: `.transition(.opacity.combined(with: .scale(0.96)))`
- Duration range: 150–350ms for UI; never > 400ms for interaction feedback

---

## Premium Detail Rules

- Never show raw debug data to non-engineers — the Debug section is collapsible in TrainerControlsPanel
- Error states: tasteful banner at top of camera area, not a modal interrupt
- Empty states: use `ContentUnavailableView` with a helpful action button
- Loading states: skeleton shimmer for > 1s waits (not a full spinner)
- BLE status: always visible in HUD — never hidden unless screen is too narrow
