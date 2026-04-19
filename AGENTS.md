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
| UserChooser | `.userChooser` | ✅ done |
| Hub | root | ✅ done (redesigned) |
| TaskPicker | `.taskPicker` | ✅ done (card grid) |
| TaskRunner | `.taskRunner(task)` | ✅ done (landscape + HUD + panel) |
| Results | `.results(summary)` | ✅ Phase 4 |
| Analysis | `.analysis(id)` | ✅ Phase 4 |
| Leaderboards | `.leaderboards` | ✅ Phase 4 |
| Reports | `.reports` | ✅ Phase 4 |
| Curriculum + Run | `.curriculum` / `.curriculumRun` | ❌ Phase 9 |
| UserManagement | `.userManagement` | ✅ Phase 4 |
| CustomTaskConfig | `.customTaskConfig` | ❌ Phase 9 |

**Flow:** App launch → UserChooser (select/create trainee) → Hub → TaskPicker → TaskRunner → Results → [Analysis / Leaderboards]

---

## Task Engines

| Engine | File | Status |
|--------|------|--------|
| KeyLock | `Core/Tasks/KeyLockTaskEngine.swift` | ✅ implemented |
| TipPositioning | `Core/Tasks/TipPositioningTaskEngine.swift` | ✅ implemented |
| RubberBand | `Core/Tasks/RubberBandTaskEngine.swift` | ✅ implemented |
| SpringsSuturing | `Core/Tasks/SpringsSuturingTaskEngine.swift` | ✅ implemented |
| ManualScoring | `Core/Tasks/ManualScoringEngine.swift` | ✅ implemented |

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

## Skills Reference

All skill reference sheets (project-specific cheat sheets) live in:
**`.cline/skills/`** — one file per domain, with project-specific APIs and patterns.

See `.cline/skills/README.md` for the dispatch table.

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

---

## 🧑 Human Instructions — What You Need to Do Manually

AI agents work entirely via terminal/filesystem. Some things MUST be done by a human in Xcode or the system. Check this section after every session.

### After Any Session Where New Files Were Created

**Problem:** Files created by the AI via terminal do NOT automatically appear in Xcode's project navigator. Xcode uses an explicit file list in `p2 app.xcodeproj/project.pbxproj` — new files are invisible to Xcode builds (and thus to the app) until added.

**BUT** — `xcodebuild` from terminal DOES pick them up if the source directory is configured with a wildcard or if the project uses folder references. The AI verifies builds with `xcodebuild`, so if it says "BUILD SUCCEEDED", the files are building. You may still need to add them to Xcode's navigator for IDE features (autocomplete, jump-to-definition) to work.

**What to do:**
1. Open `p2 app.xcodeproj` in Xcode
2. In the Project Navigator (⌘1), check whether new files/folders listed in the commit message appear
3. If a folder or file is missing: right-click the nearest parent group → "Add Files to 'p2 app'..." → navigate to the file → ensure "Add to target: p2 app" is checked → Add
4. Newly added groups should appear under the correct `Core/` or `Features/` parent

**New files added this session that may need Xcode linking:**
- `Core/DesignSystem/DesignTokens.swift`
- `Core/DesignSystem/GlassCard.swift`

---

### Running the App

**On Simulator (easiest, no signing needed):**
- In Xcode: select "iPad Pro 13-inch (M5)" or "iPad Pro 13-inch (M4)" simulator from the device picker → `Cmd+R`
- Or via terminal (see "Xcode Build Command" below)

**On Your Real iPad (Amit's iPad):**
1. Connect iPad via USB
2. In Xcode: select "Amit's iPad" from device picker
3. First time: Xcode → Product → Destination → Manage Run Destinations → trust the device
4. You may need to go to Settings → General → VPN & Device Management → trust the developer certificate
5. `Cmd+R` to build and run

**Checking camera + BLE on simulator vs real device:**
- Camera: works on real iPad only — simulator shows a black preview (expected)
- BLE / HandX device: real iPad only — simulator uses `MockHandXBLEManager` (auto-injected by AI code via `#if targetEnvironment(simulator)`)
- CoreML inference: works on both, but Neural Engine only fires on real device

---

### After the AI Adds a New SwiftData Model

When a new `@Model` class is added (e.g., `CurriculumRecord`):
1. Open `p2_appApp.swift`
2. Find the `.modelContainer(for: [...])` call
3. Add the new model type to the array — e.g., `CurriculumRecord.self`
4. If you skip this, the app will crash at launch with a SwiftData schema error

---

### After the AI Adds New Sound or Model Assets

Sound files live at a symlinked path. If a new `.mp3` or `.mlpackage` appears but doesn't play/load:
1. In Xcode Project Navigator: expand `p2 app` → look for the `sounds` or `models` group
2. Right-click → "Add Files..." → add the new file → ensure "Copy items if needed" is **unchecked** (they're symlinked) and "Add to target: p2 app" is **checked**
3. For `.mlpackage` models: same process, but under the `models` group

---

### After the AI Modifies `Info.plist` or Entitlements

These files are sensitive — Xcode sometimes regenerates them. If the AI edits them and Xcode shows a merge conflict:
1. Open `p2 app/p2 app.xcodeproj` → select the project in navigator → "Signing & Capabilities"
2. Verify camera usage description, Bluetooth usage description, and any new keys are present
3. If not: add them via the "+" button in the Info tab, or edit `Info.plist` directly in Xcode

---

### Switching Between AI Agents (Cline / Codex / Claude)

All agents use the same `CLAUDE.md` (= `.clinerules` = `AGENTS.md`) as their master context. When switching:
1. **Always start a new agent session by pasting the ⚡ NEXT AGENT PROMPT** block from the bottom of `CLAUDE.md`
2. The agent will read CLAUDE.md first and know exactly what commit it's continuing from
3. After the session, verify the agent updated the Session Audit and NEXT AGENT PROMPT sections and committed

**Sync enforcement (pre-commit hook):**
The hook in `.githooks/pre-commit` auto-syncs all three files on every commit:
- Claude edits `CLAUDE.md` → hook copies to `.clinerules` + `AGENTS.md`
- Cline edits `.clinerules` → hook copies to `CLAUDE.md` + `AGENTS.md`
- Codex edits `AGENTS.md` → hook copies to `CLAUDE.md` + `.clinerules`
- Two files staged with different content → commit blocked with error

**After a fresh clone or new worktree, run once:**
```bash
git config core.hooksPath .githooks
```
This is required for any machine/agent that clones the repo fresh.

---

## Session State

> Session state, completed phases, build history, and what to do next lives in a separate file:
>
> **`SESSION_AUDIT.md`** (project root) — updated after every commit.

**Quick status:** Phases 0–8 complete + device bug fixes (model lifecycle, camera session, overlay NaN). Phase 9 (Curriculum + CustomTaskConfig) is next. See SESSION_AUDIT.md for full detail.

### Design Token Quick Reference

```swift
// Colors
Color.hxCyan        // primary accent (electric cyan)
Color.hxAmber       // HandX device status
Color.hxSuccess     // target reached
Color.hxDanger      // failure/drop
Color.hxWarning     // caution
Color.hxBackground  // OLED black
Color.hxSurface     // card surface
Color.hxSurfaceRaised // elevated surface

// Fonts
Font.hxDisplay      // 52pt bold rounded (hero scores)
Font.hxTitle1       // 32pt bold rounded
Font.hxHeadline     // 17pt semibold rounded
Font.hxBody         // 15pt regular rounded
Font.hxMonoDisplay  // 48pt bold mono (score counter)
Font.hxMonoBody     // 14pt mono (telemetry values)
Font.hxCaption      // 11pt medium (labels)

// Spacing + Radius
HXSpacing.sm/md/lg/xl   // 8/12/16/24
HXRadius.sm/md/lg/xl    // 8/12/16/24

// Modifiers
.glassCard()             // standard glass card
.interactiveGlassCard()  // tappable card with press state
.hudGlass()              // capsule HUD strip
StatusDot(color:, isActive:)  // animated BLE/camera dot
```

---

## ⚡ NEXT AGENT PROMPT — copy-paste to start the next session

```
You are continuing work on the HandX Training Hub — a production iPad surgical 
instrument training app (SwiftUI, iOS 26, CoreML YOLO, BLE).

Working directory:  /Users/amitm/tk_models/ipad app/p2 app/p2 app/p2 app/
Git repo:           /Users/amitm/tk_models/ipad app/p2 app/p2 app/
Branch:             main  (build clean 0 errors, 2026-04-19)
Master context:     /Users/amitm/tk_models/ipad app/p2 app/p2 app/CLAUDE.md  ← READ THIS FIRST
Session state:      /Users/amitm/tk_models/ipad app/p2 app/p2 app/SESSION_AUDIT.md  ← what's done/pending
Skills reference:   /Users/amitm/tk_models/ipad app/p2 app/p2 app/.cline/skills/  ← per-domain cheat sheets
Full plan:          /Users/amitm/.claude/plans/staged-inventing-kite.md
Memory files:       /Users/amitm/.claude/projects/-Users-amitm-tk-models-ipad-app-p2-app-p2-app-p2-app/memory/

COMPLETED (do not redo): Phases 0–8 + bug fix passes Fix-A and Fix-B.
  See SESSION_AUDIT.md for full commit log and architecture decisions.

KEY ARCHITECTURE DECISIONS FROM FIX-B (respect these):
  - Camera session stays running for the entire app lifetime.
    stopFrameSources() calls cameraService.stopPublishing() NOT stopSession().
    Only refreshPreviewSource() with previewVisible=false calls stopSession().
  - Task models: loaded on-demand in RunnerCoordinator.prepare(), released in finish().
    Instrument model: loaded once in AppModel.bootstrap(), never released.
    No prefetch in TaskPickerView.
  - prepare() calls stopWorkers() to clear workers from previous task BEFORE creating
    new workers in beginPreviewInference(). This ensures correct model per task.

START HERE — Phase 9 (Curriculum + CustomTaskConfig):
  Skills: ios-ai-ml-skills:swiftui-animation, ios-ai-ml-skills:swiftdata,
          ios-ai-ml-skills:swiftui-liquid-glass, ios-ai-ml-skills:swiftui-navigation

  9.1 Features/Curriculum/CurriculumView.swift
      — Browse curriculum programs (structured sequences of tasks)
      — @Query on CurriculumRecord
      — Card grid matching TaskPicker style

  9.2 Features/Curriculum/CurriculumRunView.swift
      — Run tasks in sequence; auto-advance on finish
      — Progress indicator: "Task 2 of 5"
      — Same landscape layout as TaskRunnerView

  9.3 Features/CustomTaskConfig/CustomTaskConfigView.swift
      — Adjust targetCount, time limit, mode for a custom run
      — Form sheet over TaskPicker

  Wire .curriculum, .curriculumRun, .customTaskConfig routes in ContentView + AppModel.

RULES:
  - After each phase: xcodebuild (command in SESSION_AUDIT.md)
  - Commit each phase separately with Co-Authored-By line
  - Update SESSION_AUDIT.md after each commit; update CLAUDE.md + sync to
    .clinerules + AGENTS.md when architecture or rules change
  - Design system is live: Color.hxCyan, Font.hxHeadline, .glassCard(), etc.
  - North star: NOT an engineer's app — every screen must be premium/clinical
  - manual_logs.txt: only read if changed since last commit (git status check first)
```
