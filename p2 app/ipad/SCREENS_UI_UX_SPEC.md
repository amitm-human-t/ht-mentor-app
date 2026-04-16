# Screens + UI/UX Spec (iPad)

## UX Goals
- Fast operator flow (minimal taps from user select → task run)
- High visibility overlays/HUD on top of rear-camera feed
- Trainer controls always reachable without hiding critical video content
- Consistent interaction model across all tasks/modes

## Navigation Map
1. **UserChooser**
2. **Hub**
3. **TaskPicker**
4. **TaskRunner**
5. **Results**
6. **Analysis**
7. **Leaderboards**
8. **Reports**
9. **Curriculum** / **CurriculumRun**
10. **UserManagement**
11. **CustomTaskConfig**

Use a SwiftUI router (`NavigationStack` + state-driven destinations). Non-linear screens (Results/Analysis overlays) can use full-screen covers.

## Global UI Requirements
- Landscape-first layout for run-critical screens.
- Touch targets >= 44pt.
- iPad split-safe design (no clipped runner controls).
- Dark and light theme support, but default to training-optimized high-contrast dark mode.

## Screen-by-screen requirements

## 1) UserChooser
- Search/select user.
- Create/edit user.
- Dominant hand selector (`left` / `right`, default `right`).
- Last active user auto-selected.

## 2) Hub
- Large action cards:
  - Start Task
  - Curriculum
  - Reports
  - Leaderboards
  - User Management
- Mini camera preview panel with source status (rear camera active).
- HandX quick status indicator (connected/disconnected).

## 3) TaskPicker
- Task cards with summary + supported modes.
- Mode pills per task.
- Locked Sprint mode gated by HandX connection status.
- Support custom task presets and curriculum-injected selections.

## 4) TaskRunner (most critical)

### Layout
- **Center:** live camera feed (rear camera)
- **Top overlay:** status, target, score, progress, timer
- **Right/Bottom panel:** trainer controls and debug toggles

- Active runs should default into a focus-oriented full-screen runner presentation with surrounding navigation minimized.

- Trainer/debug controls should be collapsed by default but reopenable with a persistent toggle.

### Primary controls
- Start / Pause / Resume
- Reset
- Exit run
- Optional: fullscreen focus mode

- The iPad implementation may treat fullscreen focus mode as the default active-run presentation.

### Trainer controls
- Skip target / skip step (where applicable)
- Manual Success / Failure / Key Dropped events
- Change target (tutorial/task specific)

### Debug controls
- Show detection boxes
- Show occlusion markers
- Show target helper line
- Show FPS/perf
- HandX HUD enable/position/scale

- In debug-video mode, embedded videos should auto-play on selection and loop until the run is stopped, reset, or exited.

### Overlay behavior
- Overlays are rendered in UI layer, not baked into camera pixels.
- Per-class detection colors and labels must remain configurable.

## 5) Results
- End-of-run summary:
  - Task/mode
  - Score
  - Duration
  - Completion / accuracy style metric
- Buttons:
  - Retry
  - Analyze
  - Back to Hub

## 6) Analysis
Tabs mirroring current app intent:
- Overview
- Task-specific
- HandX
- AI notes placeholder (v1 can be basic text insights)

## 7) Leaderboards
- Task + mode filters.
- Dynamic main metric column:
  - Sprint: best time
  - Timer/survival-like: highest completion count
  - Score modes: highest score

## 8) Reports
- Aggregate stats by user/task/date range.
- Keep lightweight and summary-focused in v1.

## 9) Curriculum & CurriculumRun
- Trainer curriculum authoring.
- Trainee flow for continuing next assigned task.

## 10) UserManagement
- CRUD users.
- Dominant hand editing.

## 11) CustomTaskConfig
- Build ad-hoc task sessions (task/mode/timer/options).

## iPad Interaction details
- Replace desktop hotkeys with explicit touch controls.
- Optional hardware keyboard shortcuts can be added later.
- Ensure no critical action requires multi-touch gestures.

## Accessibility baseline
- Dynamic Type support for non-overlay textual screens.
- VoiceOver labels for buttons and status fields.
- Sufficient color contrast for overlays (or optional colorblind palette in settings).
