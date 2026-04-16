# iPad Implementation Plan (Execution Roadmap)

## Phase 0 — Project bootstrap
1. Create Xcode workspace (`HandXPad`) with SwiftUI app lifecycle.
2. Add module folders matching `ipad/ARCHITECTURE_REQUIREMENTS.md`.
3. Add resource folders (`Resources/Models`, `Resources/Sounds`, `Resources/Icons`).
4. Add startup diagnostics for required assets.

## Phase 1 — Core runtime foundations
1. Implement `CameraService` (rear camera capture).
2. Implement `RunStateMachine` + `RunnerCoordinator`.
3. Implement `TaskEngine` contracts and base task scaffold.
4. Implement overlay rendering layer + HUD layer.

## Phase 2 — ML and inference pipeline
1. Convert required `.pt` models to CoreML.
2. Build `CoreMLModelRegistry` and async workers:
   - task worker
   - instrument worker
3. Add inference tuning controls (confidence/IoU/max-det).
4. Validate class-map parity + overlay alignment.

## Phase 3 — HandX BLE integration
1. Build `HandXBLEManager` + decoder.
2. Integrate normalized samples into runner inputs.
3. Implement Locked Sprint gating and disconnect handling.
4. Add mock BLE path for simulator/testing.

## Phase 4 — Task parity implementation
Implement and verify in this order:
1. KeyLock
2. Tip Positioning
3. Rubber Band
4. Springs Suturing
5. Manual scoring

For each task:
- state machine parity
- score/progress parity
- overlay parity
- trainer action parity

## Phase 5 — Screens and trainer workflows
1. UserChooser
2. Hub
3. TaskPicker
4. TaskRunner
5. Results + Analysis
6. Leaderboards + Reports
7. Curriculum + UserManagement + CustomTaskConfig

## Phase 6 — Data and privacy
1. Implement local repositories for users/runs/leaderboards.
2. Persist summary-only run records.
3. Ensure transient raw run data is pruned after summary generation.
4. Add user data deletion controls.

## Phase 7 — QA, optimization, release readiness
1. Functional parity checklist signoff for all tasks/modes.
2. Performance profiling on target iPad hardware.
3. BLE reliability stress tests.
4. Asset completeness validation (sounds/models/icons).
5. Pilot release build and trainer UX review.

## Definition of done for v1
- All current tasks available and playable.
- Core overlays/trainer controls fully usable on iPad.
- HandX BLE works for required modes.
- High-level stats and local leaderboards available.
- No persistent raw session/video storage.
