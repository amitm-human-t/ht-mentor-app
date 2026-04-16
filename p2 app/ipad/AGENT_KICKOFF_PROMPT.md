# iPad Build Agent Kickoff Prompt

Copy/paste this into the implementation agent that will build the iPad app.

---

You are building the **HandX Training Hub iPad app** in Xcode.

## Mission
Implement an iPad-native app (SwiftUI-first, UIKit bridges where needed) with behavior parity to the current desktop trainer for all in-scope tasks and core workflows.

## Non-negotiable decisions (already locked)
1. UI stack: **SwiftUI-first**
2. Storage: **local-only in v1**, cloud-ready architecture
3. Supported hardware for v1: **iPad Pro M1/M2/M4 only**
4. Locked Sprint BLE disconnect policy: **pause + 10s grace + auto-end if not reconnected**
5. No v1 video recording; raw run telemetry is transient and pruned after summary extraction

## Required reading order (do not skip)
1. `ipad/README.md`
2. `ipad/ARCHITECTURE_REQUIREMENTS.md`
3. `ipad/IMPLEMENTATION_PLAN.md`
4. `ipad/XCODE_ASSET_MIGRATION.md`
5. `ipad/ML_COREML_PIPELINE_SPEC.md`
6. `ipad/BLE_HANDX_SPEC.md`
7. `ipad/TASKS_AND_GAMEPLAY_SPEC.md`
8. `ipad/SCREENS_UI_UX_SPEC.md`
9. `ipad/DATA_STATS_PRIVACY_SPEC.md`
10. `ipad/DEVICE_SUPPORT_PERFORMANCE_MATRIX.md`
11. `ipad/IOS_PERMISSIONS_AND_PRIVACY_KEYS.md`
12. `ipad/CALIBRATION_AND_SETUP_FLOW.md`
13. `ipad/FAILURE_RECOVERY_UX_SPEC.md`
14. `ipad/RELEASE_ACCEPTANCE_CHECKLIST.md`

## v1 scope
- Tasks: KeyLock, Tip Positioning, Rubber Band, Springs Suturing, Manual scoring
- Sessions: full runner lifecycle + trainer controls + overlays
- Users: create/select/edit + dominant hand + persistent summaries
- BLE: HandX integration for required modes
- ML: CoreML conversion + runtime for task model + always-on instrument model

## First implementation milestone (Day 1–2)
1. Create Xcode app/module skeleton matching `ARCHITECTURE_REQUIREMENTS.md`
2. Set up resource tree exactly per `XCODE_ASSET_MIGRATION.md`
3. Add startup diagnostics for required assets
4. Add permission preflight scaffolding (camera + bluetooth)
5. Implement camera service + basic task-runner shell state machine (no full task logic yet)

## Execution order (must follow)
1. Runtime core (camera, runner state machine, overlay layer)
2. CoreML pipeline (task worker + instrument worker)
3. BLE pipeline + disconnect/reconnect behavior
4. Task parity implementation in this order:
   - KeyLock
   - Tip Positioning
   - Rubber Band
   - Springs Suturing
   - Manual scoring
5. Screens/workflows completion
6. Data/privacy completion
7. Release acceptance checks

## Implementation guardrails
- Keep task/game logic decoupled from UI view code.
- Do not block main thread with inference.
- Prefer dropping stale frames over queue growth.
- Keep overlays in UI rendering layer, not baked into captured camera pixels.
- Keep strict target counting and non-recycled IDs within session.

## Done criteria
- Every section in `ipad/RELEASE_ACCEPTANCE_CHECKLIST.md` is satisfied.
- All v1 tasks/modes pass parity checks.
- Device, BLE, permissions, and failure-recovery flows behave exactly as specified.

## Reporting format expected from implementation agent
For each completed phase:
- What was implemented
- Files/modules created/changed
- What remains
- Risks/unknowns requiring product decision

---

If any architectural decision is ambiguous, ask before implementing.
