# iPad Architecture + Requirements (SwiftUI-first)

## 1) Product Intent
Create an iPad-native HandX Training Hub that preserves training fidelity from the desktop app while using iOS-native components for camera, BLE, rendering, persistence, and audio.

## 2) Architectural Principles (derived from current contracts)
1. **Headless task logic remains separate from UI**
   - Keep task state machines and scoring logic independent from SwiftUI views.
2. **Single camera owner**
   - One session service owns AV capture lifecycle; tasks consume frames only.
3. **Parallel inference workers**
   - Task model inference and instrument-tip inference run independently and merge in a coordinator.
4. **Stable IDs and strict counting invariants**
   - Preserve slot/pin/pole tracking semantics and non-recycled IDs within session.
5. **Debugability preserved**
   - Keep toggles for overlays, FPS/perf indicators, and task-debug status for trainer usage.
6. **Privacy-oriented data minimization**
   - Keep high-level stats; prune raw event payloads after summary computation.

## 3) Recommended iOS module layout
```
HandXPad/
  App/
    HandXPadApp.swift
    AppRouter.swift
  Core/
    Contracts/
      TaskEngine.swift
      TaskInputs.swift
      TaskOutputs.swift
    Session/
      RunnerCoordinator.swift
      RunStateMachine.swift
      SessionSummaryBuilder.swift
    Camera/
      CameraService.swift
      CameraFrameBus.swift
    Inference/
      ModelRuntime.swift
      TaskInferenceWorker.swift
      InstrumentInferenceWorker.swift
      CoreMLModelRegistry.swift
    BLE/
      HandXBLEManager.swift
      HandXPacketDecoder.swift
      HandXInputProvider.swift
    Storage/
      LocalStore.swift
      LeaderboardRepository.swift
      UserRepository.swift
      RunSummaryRepository.swift
    Audio/
      AudioService.swift
      SoundCatalog.swift
  Features/
    Hub/
    TaskPicker/
    TaskRunner/
    Results/
    Analysis/
    Leaderboards/
    Reports/
    Curriculum/
    UserManagement/
  Tasks/
    KeyLock/
    TipPositioning/
    RubberBand/
    SpringsSuturing/
    Manual/
  Resources/
    Models/
    Sounds/
    Icons/
```

## 4) Runtime data flow
1. `CameraService` captures rear-camera frames.
2. `RunnerCoordinator` fans out each frame to:
   - task-specific model worker
   - instrument-tip model worker
3. `HandXInputProvider` polls normalized device sample.
4. Coordinator builds `TaskInputs` and calls active task engine step.
5. Task returns structured output:
   - score/status/progress
   - tracked entities/state transitions
   - overlay primitives (lines/boxes/targets)
6. UI renders overlays + HUD from output.
7. Summary builder computes high-level run stats and persists summary only.

## 5) Required contracts to define in Swift

### `TaskEngine`
- `start()`
- `pause()`
- `reset()`
- `configure(_ config: TaskConfig)`
- `step(frame: CVPixelBuffer, inputs: TaskInputs) -> TaskStepOutput`

### `TaskInputs`
- HandX sample (orientation, joystick, roll, grip, buttons/state)
- instrument tip payload (`Tip`, `manual` optional bboxes)
- timing (`elapsed`, mode timers)
- trainer actions (skip target, success/fail manual events)

### `TaskStepOutput`
- `statusText`
- `score`
- `targetInfo` (slot/pin/pole labels)
- `progress` (`completed`, `total`)
- `events` (state changes/score events for summary builder)
- `overlayPayload`

## 6) Performance requirements
- Primary run target: smooth live pipeline, user-perceived 30 FPS+ on supported iPads.
- Inference budget:
  - task model + instrument model combined should avoid UI thread blocking.
- Hard rule: no heavy inference on main thread.
- Frame drop strategy: allow stale frame discard instead of queue growth.

## 7) Device + platform requirements
- iPadOS target (to be finalized by dev team; recommended iPadOS 17+ baseline).
- Rear camera only for training run capture.
- BLE required for HandX-enabled modes.
- Audio playback for effects, callouts, and guidance.

## 8) Functional parity checklist
- [ ] Task runner lifecycle: idle/running/paused/finished/error
- [ ] All existing tasks and modes available (including locked sprint gating)
- [ ] Overlay toggles and target helper visuals
- [ ] Trainer controls/buttons during run
- [ ] Users, sessions, leaderboard summary, and basic stats
- [ ] Analysis views with high-level metrics

## 9) Non-goals for v1
- Full raw event archival like desktop JSONL + frame-level DB mirror
- On-device video recording and annotated exports
- Complex cloud backend (architecture should be cloud-ready only)
