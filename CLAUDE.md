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

## Session Audit — Last Updated 2026-04-17

### Git State

Branch: `claude-branch` (off `main`)
Commits so far:
- `8b429a1` — Initial commit (project skeleton)
- `ac181e8` — Phase 0+1.1: CLAUDE.md/AGENTS.md/.clinerules + full @Observable migration
- `302d582` — Phase 1.2+1.5+1.6: Design system, coordinate fix, overlay colors
- `c29a7db` — CLAUDE.md session audit + handoff instructions
- `7d19e96` — Next-agent prompt block added
- `1bcf070` — Human Instructions + pre-commit hook (first version)
- `6d64e6b` — Bidirectional hook + .githooks/ tracked directory
- `7e37235` — Phase 1.3+1.4: BLE mock + disconnect policy

Current build: **0 errors** (generic/platform=iOS Simulator)

### Completed Phases

| Phase | What was done |
|-------|--------------|
| 0 | Created CLAUDE.md, .clinerules, AGENTS.md at project root |
| 1.1 | Full @Observable migration (7 classes, all view files) |
| 1.2 | PreviewCoordinate + layerRectConverted coord fix (mentor-tests validated) |
| 1.3 | HandXBLEProvider protocol + MockHandXBLEManager (animated, simulator-injected) |
| 1.4 | BLE disconnect policy: disconnectCountdown + 10s Task + BLEReconnectOverlay |
| 1.5 | DesignTokens.swift + GlassCard.swift (full design system) |
| 1.6 | OverlayColor enum + OverlayElement.box carries color |

### NOT YET DONE — Pick up here in next session

**Phase 2.1 — UserChooserView** ← START HERE
- Route: add `.userChooser` to `AppRoute` in `AppModel.swift`
- New file: `Features/UserChooser/UserChooserView.swift`
- Landscape split: left panel (280pt, scrollable) = user list with search
- Right panel: create/edit form — displayName TextField, DominantHand picker, avatar grid (SF Symbol initials avatar), Save button
- `UserDefaults.lastActiveUserID` auto-selects last trainee on launch
- Add `dominantHand: DominantHand` to `TaskConfig` in `TaskContracts.swift`
- Skills: `ios-ai-ml-skills:swiftui-layout-components`, `ios-ai-ml-skills:swiftdata`

**Phase 2.2+2.3 — Hub Redesign + TaskPicker card grid**
- Hub: `GlassEffectContainer`, left-panel (user chip + HandX dot + mini camera preview) + 2×3 action card grid
- TaskPicker: `LazyVGrid` card layout, `.interactiveGlassCard()`, zoom transitions via `@Namespace`
- Skills: `ios-ai-ml-skills:swiftui-liquid-glass`, `ios-ai-ml-skills:swiftui-layout-components`

**Phase 3 — TaskRunner Full Overhaul**
- `RunnerHUDView.swift`: score with `.contentTransition(.numericText)`, progress ring, timer, BLE `StatusDot`
- `TrainerControlsPanel.swift`: `DisclosureGroup` sections (Run Controls / Trainer Actions / Debug / HandX Live / Video)
- Landscape layout: camera feed (flexible) + panel (320pt collapsible, trailing)
- Skills: `ios-ai-ml-skills:swiftui-animation`, `ios-ai-ml-skills:swiftui-layout-components`

**Phase 4 — Results/Analysis/Leaderboards/Reports/UserManagement**
**Phase 5 — Task Engines (TipPositioning, RubberBand, SpringsSuturing, Manual)**
**Phase 6+7+8 — Audio expansion, EnrichedRunPayload, AsyncStream inference workers**

### Xcode Build Command

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build \
  -project "/Users/amitm/tk_models/ipad app/p2 app/p2 app/p2 app.xcodeproj" \
  -scheme "p2 app" \
  -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.4" \
  -configuration Debug
```

### Key References

- Coordinate fix pattern: `/Users/amitm/tk_models/ipad app/mentor tests/mentor model tests/mentor model tests/CameraViewController.swift` line 726–733
- Plan file: `/Users/amitm/.claude/plans/staged-inventing-kite.md` (full 10-phase plan)
- Memory files: `/Users/amitm/.claude/projects/-Users-amitm-tk-models-ipad-app-p2-app-p2-app-p2-app/memory/`

### Design Token Quick Reference

```swift
// Colors
Color.hxCyan       // primary accent (electric cyan)
Color.hxAmber      // HandX device status
Color.hxSuccess    // target reached
Color.hxDanger     // failure/drop
Color.hxWarning    // caution

// Fonts
Font.hxDisplay     // 52pt bold rounded
Font.hxTitle1      // 32pt bold rounded
Font.hxHeadline    // 17pt semibold rounded
Font.hxBody        // 15pt regular rounded
Font.hxMonoDisplay // 48pt bold mono (scores)
Font.hxMonoBody    // 14pt mono (telemetry)

// Modifiers
.glassCard()                         // standard glass card
.interactiveGlassCard()              // tappable card with press state
.hudGlass()                          // capsule HUD strip
StatusDot(color:, isActive:)         // animated BLE/camera dot
```

---

## ⚡ NEXT AGENT PROMPT — copy-paste to start the next session

```
You are continuing work on the HandX Training Hub — a production iPad surgical 
instrument training app (SwiftUI, iOS 26, CoreML YOLO, BLE).

Working directory:  /Users/amitm/tk_models/ipad app/p2 app/p2 app/p2 app/
Git repo:           /Users/amitm/tk_models/ipad app/p2 app/p2 app/
Branch:             claude-branch  (4 commits ahead of main, build clean 0 errors)
Master context:     /Users/amitm/tk_models/ipad app/p2 app/p2 app/CLAUDE.md  ← READ THIS FIRST
Full plan:          /Users/amitm/.claude/plans/staged-inventing-kite.md
Memory files:       /Users/amitm/.claude/projects/-Users-amitm-tk-models-ipad-app-p2-app-p2-app-p2-app/memory/

COMPLETED SO FAR (do not redo):
  Phase 0    — CLAUDE.md / .clinerules / AGENTS.md created and synced
  Phase 1.1  — Full @Observable migration (AppModel, RunnerCoordinator, 
               HandXBLEManager, CameraService, DebugVideoFrameSource, 
               PermissionCenter, AudioService + all views)
  Phase 1.2  — YOLO→screen coord fix: PreviewCoordinate + layerRectConverted 
               (pattern from mentor-tests reference app)
  Phase 1.5  — DesignTokens.swift + GlassCard.swift (full design system)
  Phase 1.6  — OverlayColor enum in TaskContracts, boxes carry color

START HERE — Phase 1.3+1.4 (BLE Mock + Disconnect Policy):
  1. Create Core/BLE/HandXBLEProvider.swift
     — protocol that mirrors HandXBLEManager's public interface
     — properties: connectionState, discoveredDevices, latestSample, statusText
     — methods: startScan(), stopScan(), connect(to:), disconnect()
  2. Create Core/BLE/MockHandXBLEManager.swift
     — conforms to HandXBLEProvider
     — @Observable, @MainActor, simulates .connected state
     — animates latestSample values (joystick, orientation changing slowly)
  3. AppModel.swift: #if targetEnvironment(simulator) inject MockHandXBLEManager
  4. RunnerCoordinator.swift: accept any HandXBLEProvider, add disconnectCountdown: Int?
  5. Disconnect during .lockedSprint + .running → pause + 10s countdown Task
     Reconnect within window → resume; timeout → finish() with reason string
  6. Create Features/TaskRunner/BLEReconnectOverlay.swift
     — full-screen modal: countdown ring (Circle().trim), "HandX Disconnected",
       activity indicator, "End Run" escape button
     — triggered when runnerCoordinator.disconnectCountdown != nil

THEN continue Phase 2.1 (UserChooserView), 2.2+2.3 (Hub + TaskPicker redesign),
then Phase 3 (TaskRunner overhaul with RunnerHUDView + TrainerControlsPanel).

RULES:
  - After each phase: build with xcodebuild (command in CLAUDE.md Session Audit)
  - Commit each phase separately with descriptive message + Co-Authored-By line
  - Update Session Audit section in CLAUDE.md after every commit
  - Sync CLAUDE.md → .clinerules and AGENTS.md after every CLAUDE.md edit
  - Always add a fresh NEXT AGENT PROMPT block at the end of CLAUDE.md
  - Use ios-ai-ml-skills:core-bluetooth skill for BLE work
  - Use ios-ai-ml-skills:swiftui-liquid-glass for Hub/TaskPicker glass UI
  - Design system is live: use Color.hxCyan, Font.hxHeadline, .glassCard() etc.
  - North star: NOT an engineer's app — every screen must look premium/clinical
```
