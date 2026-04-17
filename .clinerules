# HandX Training Hub — Project Intelligence

> iPad surgical instrument training app. CoreML YOLO detection + BLE (HandX device) + SwiftUI.
> Built for iPad Pro M1/M2/M4. iOS 26 minimum deployment target.

---

## North Star (non-negotiable)

1. **Not an engineer's app.** Beautiful, designed, premium. No raw data dumps, no ugly debug panels. Trainer controls must feel crafted.
2. **Fluid / zero lag.** 60 FPS everywhere. Tap responses <100ms. Any jank is a bug.
3. **Modular.** Every view is a small, focused, independently understandable component. No monoliths. Extract aggressively.
4. **UI/UX first.** Every decision starts with "how does this feel?" before "how does this work?".
5. **Dark, premium, clinical.** High-end fitness tracker meets surgical suite. Precise, confident, OLED-black.

---

## Project Paths

| Location | Path |
|----------|------|
| Source files | `/Users/amitm/tk_models/ipad app/p2 app/p2 app/p2 app/` |
| Xcode project | `/Users/amitm/tk_models/ipad app/p2 app/p2 app/p2 app.xcodeproj/` |
| Spec docs (14 files) | `/Users/amitm/tk_models/ipad app/p2 app/ipad/` |
| Old reference app | `/Users/amitm/humanx-app-bit/` — light inspiration only, don't copy design |
| Git branch | `claude-branch` |

---

## Architecture

```
p2 app/
├── App/              AppModel (@Observable)
├── Core/
│   ├── Assets/       AssetCatalog, StartupDiagnostics
│   ├── Audio/        AudioService (background + callout + effect players)
│   ├── BLE/          HandXBLEManager (actor), HandXBLEProvider (protocol), MockHandXBLEManager
│   ├── Camera/       CameraService, CameraFrameBus (actor), CameraPreviewView
│   ├── Contracts/    TaskContracts (all shared types)
│   ├── DesignSystem/ DesignTokens, GlassCard
│   ├── Device/       DeviceSupport
│   ├── Diagnostics/  AppLogger
│   ├── Inference/    CoreMLModelRegistry (actor), InferenceWorkers (actors)
│   ├── Permissions/  PermissionCenter
│   ├── Session/      RunnerCoordinator (@Observable), RunStateMachine, SessionSummaryBuilder, UserDefaultsStore
│   ├── Storage/      StorageModels (SwiftData), Repositories
│   └── Tasks/        KeyLockTaskEngine, TipPositioningTaskEngine, RubberBandTaskEngine,
│                     SpringsSuturingTaskEngine, ManualScoringEngine, DetectionColorPalette
├── Features/
│   ├── Hub/          HubView
│   ├── UserChooser/  UserChooserView
│   ├── TaskPicker/   TaskPickerView
│   ├── TaskRunner/   TaskRunnerView, RunnerHUDView, TrainerControlsPanel, BLEReconnectOverlay
│   ├── Preview/      AppPreviewStageView, PreviewOverlayView
│   ├── Results/      ResultsView
│   ├── Analysis/     AnalysisView
│   ├── Leaderboards/ LeaderboardsView
│   ├── Reports/      ReportsView
│   ├── Curriculum/   CurriculumView, CurriculumRunView
│   ├── UserManagement/ UserManagementView
│   ├── CustomTaskConfig/ CustomTaskConfigView
│   ├── BLE/          BLEConsoleView
│   ├── Diagnostics/  DiagnosticsView
│   └── Permissions/  PermissionCenterView
```

### Key Patterns

- **State:** `@Observable` for `AppModel` + `RunnerCoordinator` (NOT `ObservableObject`). Inject via `.environment(appModel)`.
- **Concurrency:** Actors for `CameraFrameBus`, `CoreMLModelRegistry`, `InferenceWorkers`, `HandXBLEManager`. Never block the main thread.
- **Inference:** Workers self-schedule via `AsyncStream(bufferingPolicy: .bufferingNewest(1))` — frame-drop over queue growth.
- **Run loop:** `RunnerCoordinator.tick()` reads inference snapshots synchronously (no await). 100ms cadence.
- **Storage:** SwiftData with `@Model` — `UserRecord`, `RunSummaryRecord`, `CurriculumRecord`. `@Query` for live bindings.
- **Navigation:** `NavigationStack` + `AppRoute` enum. Zoom transitions for task cards. All routes are deep-linkable.

---

## iOS 26 — Use These APIs Freely

```swift
// Liquid Glass (iOS 26)
.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
.buttonStyle(.glass)
.buttonStyle(.glassProminent)
GlassEffectContainer { ... }

// Smooth animations
.contentTransition(.numericText(countsDown: false))      // score/timer numbers
PhaseAnimator([false, true], trigger: id) { phase in ... } // pulse effects
.navigationTransition(.zoom(sourceID: id, in: ns))        // screen transitions

// Data
@Observable final class ...                               // replaces ObservableObject
@Query(sort: \RunSummaryRecord.score, order: .reverse)    // SwiftData live binding
```

Always add iOS 17 fallback for `.glassEffect()`:
```swift
if #available(iOS 26, *) {
    view.glassEffect(...)
} else {
    view.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
}
```

---

## Design System

### Colors (OLED Dark — clinical precision)

```swift
// In Core/DesignSystem/DesignTokens.swift
extension Color {
    // Backgrounds
    static let hxBg         = Color(hex: "020617")  // OLED black
    static let hxSurface    = Color(hex: "0E1223")  // card surface
    static let hxSurface2   = Color(hex: "1E293B")  // elevated surface
    static let hxBorder     = Color(hex: "334155")  // borders/dividers

    // Accents
    static let hxCyan       = Color(hex: "0891B2")  // primary accent (clinical teal)
    static let hxCyanLight  = Color(hex: "22D3EE")  // highlights, active states
    static let hxGreen      = Color(hex: "22C55E")  // success, completion
    static let hxAmber      = Color(hex: "F59E0B")  // warning, HandX status
    static let hxRed        = Color(hex: "EF4444")  // failure, drop, error

    // Text
    static let hxText       = Color(hex: "F8FAFC")  // primary text
    static let hxTextMuted  = Color(hex: "94A3B8")  // secondary text
    static let hxTextDim    = Color(hex: "475569")  // disabled/tertiary
}
```

### Typography (SF system fonts — zero bundle overhead)

```swift
extension Font {
    // Display: large HUD numbers, hero scores
    static let hxDisplay    = Font.system(size: 48, weight: .bold, design: .rounded)
    // Title: screen titles, section headers
    static let hxTitle      = Font.system(size: 28, weight: .bold, design: .rounded)
    // Headline: card titles
    static let hxHeadline   = Font.system(size: 18, weight: .semibold, design: .default)
    // Body: general text
    static let hxBody       = Font.system(size: 16, weight: .regular, design: .default)
    // Caption: labels, tags, secondary info
    static let hxCaption    = Font.system(size: 12, weight: .medium, design: .default)
    // Mono: scores, timers, counters — always monospaced for stable width
    static let hxMono       = Font.system(size: 24, weight: .bold, design: .monospaced)
    static let hxMonoSm     = Font.system(size: 14, weight: .regular, design: .monospaced)
}
```

### Animation Tokens

```swift
// Micro-interactions: 150–250ms ease-out
.animation(.easeOut(duration: 0.2), value: ...)

// State transitions: spring for natural feel
.animation(.spring(response: 0.35, dampingFraction: 0.7), value: ...)

// Enter: ease-out  |  Exit: faster (0.15s ease-in)
// Score counter: .snappy  |  Progress ring: .smooth

// Overlay pulse target ring
PhaseAnimator([false, true], trigger: targetID) { pulsed in
    Circle()
        .scaleEffect(pulsed ? 1.08 : 1.0)
        .opacity(pulsed ? 0.9 : 0.6)
} animation: { _ in .easeInOut(duration: 0.7) }
```

### Detection Colors (per task class)

```swift
// tip=cyan, slot=orange, hover=yellow, in=green
// key=white, logo=teal, ring=pink, bands=yellow, pin=orange
// spring=orange, loop=yellow, loop_needle=green, loop_thread=teal
```

---

## Screens (11 total)

| Screen | Route | Status |
|--------|-------|--------|
| UserChooser | `.userChooser` | needs build |
| Hub | root | needs redesign |
| TaskPicker | `.taskPicker` | needs redesign |
| TaskRunner | `.taskRunner(task)` | needs overhaul |
| Results | `.results(summary)` | needs build |
| Analysis | `.analysis(id)` | needs build |
| Leaderboards | `.leaderboards` | needs build |
| Reports | `.reports` | needs build |
| Curriculum + Run | `.curriculum` / `.curriculumRun` | needs build |
| UserManagement | `.userManagement` | needs build |
| CustomTaskConfig | `.customTaskConfig` | needs build |

**Flow:** App launch → UserChooser (select/create trainee) → Hub → TaskPicker → TaskRunner → Results → [Analysis / Leaderboards]

---

## Task Engines

| Engine | File | Status |
|--------|------|--------|
| KeyLock | `Core/Tasks/KeyLockTaskEngine.swift` | ✅ implemented |
| TipPositioning | `Core/Tasks/TipPositioningTaskEngine.swift` | ❌ PlaceholderTaskEngine |
| RubberBand | `Core/Tasks/RubberBandTaskEngine.swift` | ❌ PlaceholderTaskEngine |
| SpringsSuturing | `Core/Tasks/SpringsSuturingTaskEngine.swift` | ❌ PlaceholderTaskEngine |
| ManualScoring | `Core/Tasks/ManualScoringEngine.swift` | ❌ PlaceholderTaskEngine |

CoreML models bundled: `keylock`, `tippos`, `rubberband`, `springs`, `instrument` (all `.mlpackage`)

---

## BLE / HandX Rules

- **Locked Sprint gating:** HandX connection required for `.lockedSprint` mode
- **Disconnect policy:** Pause immediately → 10s reconnect countdown → reconnect resumes / timeout auto-ends with `.device_disconnect_timeout`
- **Simulator:** `#if targetEnvironment(simulator)` injects `MockHandXBLEManager` (simulated connected state)
- Service UUID: `DD90EC52-0000-4357-891A-26D580F709EF`

---

## Performance Rules

- **No UI thread blocking.** All camera, inference, BLE processing on background actors.
- **Frame drop over queue.** `CameraFrameBus.subscribe()` uses `.bufferingNewest(1)` — workers always get latest frame.
- **Inference is self-scheduled.** Workers use `AsyncStream` — they don't get polled by the run loop.
- **Run loop reads, doesn't await.** `RunnerCoordinator.tick()` reads `worker.latestSnapshot` synchronously.
- **Isolated subtrees.** `RunnerHUDView` reads only score/progress. `PreviewOverlayView` reads only overlayPayload. Separate re-render budgets.
- **Thermal monitor.** Reduce inference rate on `.critical` thermal state.

---

## Multi-Agent Workflow (REQUIRED)

Always invoke the matching skill when working in a domain:

| Domain | Skill |
|--------|-------|
| @Observable, view patterns, env injection | `ios-ai-ml-skills:swiftui-patterns` |
| Liquid Glass, .glassEffect | `ios-ai-ml-skills:swiftui-liquid-glass` |
| Animations (numericText, PhaseAnimator, zoom) | `ios-ai-ml-skills:swiftui-animation` |
| Layout (grids, splits, GeometryReader) | `ios-ai-ml-skills:swiftui-layout-components` |
| Navigation (routes, transitions) | `ios-ai-ml-skills:swiftui-navigation` |
| SwiftData (@Query, FetchDescriptor) | `ios-ai-ml-skills:swiftdata` |
| Swift Charts | `ios-ai-ml-skills:swift-charts` |
| CoreBluetooth | `ios-ai-ml-skills:core-bluetooth` |
| CoreML / Vision | `ios-ai-ml-skills:coreml` |
| Actors, AsyncStream, Swift concurrency | `ios-ai-ml-skills:swift-concurrency` |
| AVFoundation (camera, audio, video) | `ios-ai-ml-skills:avkit` |
| Performance profiling | `ios-ai-ml-skills:swiftui-performance` |
| Unit / integration tests | `ios-ai-ml-skills:swift-testing` |
| On-device AI / Neural Engine | `ios-ai-ml-skills:apple-on-device-ai` |
| UI/UX design decisions | `ui-ux-pro-max` |

---

## Spec Documents (read before changing behavior)

All 14 spec files live at `/Users/amitm/tk_models/ipad app/p2 app/ipad/`:
- `ARCHITECTURE_REQUIREMENTS.md`
- `SCREENS_UI_UX_SPEC.md`
- `BLE_HANDX_SPEC.md`
- `TASKS_AND_GAMEPLAY_SPEC.md`
- `DATA_STATS_PRIVACY_SPEC.md`
- `ML_COREML_PIPELINE_SPEC.md`
- `IMPLEMENTATION_PLAN.md`
- `FAILURE_RECOVERY_UX_SPEC.md`
- `CALIBRATION_AND_SETUP_FLOW.md`
- `DEVICE_SUPPORT_PERFORMANCE_MATRIX.md`
- `IOS_PERMISSIONS_AND_PRIVACY_KEYS.md`
- `XCODE_ASSET_MIGRATION.md`
- `RELEASE_ACCEPTANCE_CHECKLIST.md`

---

## Hard Rules

- Minimum touch target: 44pt everywhere
- Landscape-first for TaskRunner and all run-critical screens
- No persistent raw telemetry — summary-only storage
- No video recording in v1
- iPad Pro M1/M2/M4 only — no iPhone, no older iPad
- All overlays rendered in UI/Metal layer — not baked into camera pixels
- `CLAUDE.md`, `.clinerules`, and `AGENTS.md` must always stay in sync

---

## Sound Assets

Located at `sounds/` (symlinked into Xcode):
- `effects/`: success, fail, finished, gameover, success2
- `backgrounds/`: background1, background2 (loop)
- `keylock/`: 1.mp3–13.mp3 (target callouts)
- `tip_positioning/`: l1–l7.mp3 (left hand), r1–r7.mp3 (right hand)
