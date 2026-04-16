# HandX Training Hub iPad Migration — Master Spec

This folder is the iPad planning package for moving from the current PyQt desktop app to an iPad-native app in Xcode.

## Goal
Build a production-grade iPad application that preserves existing training behavior (tasks, overlays, sessions, controls, scoring), with:
- SwiftUI-first UI (UIKit bridges where needed)
- CoreML-based inference pipeline (converted from Ultralytics YOLO `.pt` models)
- Rear camera live pipeline
- HandX BLE support
- Local-first storage for users/leaderboards/basic stats
- Session-level raw telemetry kept only temporarily and deleted after summarization

## Scope (confirmed)
v1 includes **all current tasks and key runner behavior**:
- KeyLock
- Tip Positioning
- Rubber Band
- Springs Suturing
- Manual scoring flow

## What to read first
1. `ipad/ARCHITECTURE_REQUIREMENTS.md`
2. `ipad/SCREENS_UI_UX_SPEC.md`
3. `ipad/TASKS_AND_GAMEPLAY_SPEC.md`
4. `ipad/ML_COREML_PIPELINE_SPEC.md`
5. `ipad/BLE_HANDX_SPEC.md`
6. `ipad/DATA_STATS_PRIVACY_SPEC.md`
7. `ipad/XCODE_ASSET_MIGRATION.md`
8. `ipad/IMPLEMENTATION_PLAN.md`
9. `ipad/DEVICE_SUPPORT_PERFORMANCE_MATRIX.md`
10. `ipad/IOS_PERMISSIONS_AND_PRIVACY_KEYS.md`
11. `ipad/CALIBRATION_AND_SETUP_FLOW.md`
12. `ipad/FAILURE_RECOVERY_UX_SPEC.md`
13. `ipad/RELEASE_ACCEPTANCE_CHECKLIST.md`
14. `ipad/AGENT_KICKOFF_PROMPT.md`

## Key product decisions captured
- UI stack: **SwiftUI-first with UIKit bridges only when necessary**
- Data strategy: **cloud-ready architecture, local-only shipping in v1**
- Logging strategy on iPad: collect runtime/session data during run, compute summaries, delete raw session payloads

## Delivery expectation from this spec package
After implementing these docs, the team should be able to move directly to:
1. Xcode project setup
2. model conversion + integration
3. BLE + camera pipeline
4. task-by-task parity implementation

## Coverage confirmation matrix (for direct Xcode handoff)
- **Tasks + modes:** covered in `TASKS_AND_GAMEPLAY_SPEC.md`
- **Sessions + runner lifecycle:** covered in `ARCHITECTURE_REQUIREMENTS.md` + `TASKS_AND_GAMEPLAY_SPEC.md`
- **Overlays + debug HUD:** covered in `SCREENS_UI_UX_SPEC.md` + `TASKS_AND_GAMEPLAY_SPEC.md`
- **Buttons + trainer controls:** covered in `SCREENS_UI_UX_SPEC.md` (TaskRunner controls + trainer actions)
- **Graphics/UI/UX:** covered in `SCREENS_UI_UX_SPEC.md` + `XCODE_ASSET_MIGRATION.md`
- **Users + leaderboards + stats:** covered in `SCREENS_UI_UX_SPEC.md` + `DATA_STATS_PRIVACY_SPEC.md`
- **Models + sounds + icons to move:** covered in `XCODE_ASSET_MIGRATION.md`
- **Supported iPad hardware + FPS expectations:** covered in `DEVICE_SUPPORT_PERFORMANCE_MATRIX.md`
- **Permissions/privacy strings + denial flows:** covered in `IOS_PERMISSIONS_AND_PRIVACY_KEYS.md`
- **Calibration/setup + pre-run health:** covered in `CALIBRATION_AND_SETUP_FLOW.md`
- **Failure handling + reconnect logic:** covered in `FAILURE_RECOVERY_UX_SPEC.md`
- **Release/TestFlight go-live gates:** covered in `RELEASE_ACCEPTANCE_CHECKLIST.md`
- **Implementation-agent direct handoff prompt:** covered in `AGENT_KICKOFF_PROMPT.md`
