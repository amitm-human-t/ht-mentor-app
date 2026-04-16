# Tasks, Modes, Overlays, and Runner Behavior Spec (iPad)

## Objective
Replicate task-level gameplay behavior from desktop with explicit iPad implementation boundaries.

## Supported tasks in v1
1. KeyLock
2. Tip Positioning
3. Rubber Band
4. Springs Suturing
5. Manual scoring

## Mode coverage target
- Freestyle
- Sprint
- Locked Sprint (HandX gated where relevant)
- Timer (where currently available)
- Survival (where currently available)
- Tutorial (where currently available)

## Shared runner behavior

### State machine
- `idle -> running -> paused -> finished -> idle`
- `error` state with recoverable reset path

### Session lifecycle
- Prepare task engine + model workers + BLE provider before first frame processing.
- Start run timer only when `running` begins.
- On finish, compute summary and persist high-level data.

### Strict counting invariant
- Only current target contributes to score/progress in competitive modes.

## Task-level requirements

## KeyLock
- Classes: `key`, `logo`, `slot`, `in`, `locked`.
- Core transitions: `slot -> in -> locked`.
- Persistent slot IDs with non-recycling within session.
- Locked Sprint requires HandX connection.
- Trainer actions to support:
  - Skip target
  - Success
  - Key dropped
  - Tutorial skip/change controls

## Tip Positioning
- Classes: `tip`, `logo`, `slot`, `hover`, `in`.
- Core transitions: `slot -> hover -> in`.
- Persistent slot IDs with non-recycling.
- Locked Sprint HandX-gated.
- Trainer actions consistent with desktop flow.

## Rubber Band
- Classes: `bands`, `pin`, `ring`, `logo` (align exact label names per converted model metadata).
- Preserve occupancy/phase semantics and pin-target progression.
- Keep robust ring/pin stability in state updates.

## Springs Suturing
- Classes: `logo`, `spring`, `blue`, `loop`, `loop_needle`, `loop_thread`.
- Preserve pole progression logic and completion states.
- Keep drift/collision and pole validity checks available in debug insights.

## Manual scoring
- No CV model requirement.
- Provide trainer-triggered scoring events and session completion support.

## Instrument tip integration
- Always-on parallel instrument model inference.
- Inject `instrument_info` equivalent into every task step.
- Track `Tip` and `manual` classes with a short TTL smoothing strategy.

## Overlay spec for iPad
- All overlays rendered in SwiftUI/Metal/UI layer (not on raw pixel buffer).
- Overlay payload should support:
  - bbox list with class labels/confidences
  - target helper line(s)
  - state markers (occlusion/debug status)
  - task-specific guides (slot/pin/pole highlights)

## Trainer panel on iPad
- Docked side sheet or bottom sheet depending on orientation.
- Required sections:
  - Controls (start/pause/reset/exit)
  - Task actions (skip/manual events)
  - Debug toggles
  - HandX live panel

## Scoring + metrics requirement (v1)
- Keep per-run high-level metrics:
  - score
  - duration
  - completion ratio
  - key task-specific counters (drops, locks, poles threaded, etc.)
- Avoid storing full raw frame-by-frame history beyond active run lifecycle.

## Parity validation checklist
- [ ] KeyLock parity accepted
- [ ] Tip Positioning parity accepted
- [ ] Rubber Band parity accepted
- [ ] Springs Suturing parity accepted
- [ ] Manual scoring parity accepted
- [ ] Shared runner controls + overlays accepted
