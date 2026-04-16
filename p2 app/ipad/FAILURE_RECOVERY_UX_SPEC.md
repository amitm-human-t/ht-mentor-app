# Failure and Recovery UX Spec (iPad)

## Objective
Define deterministic runtime behavior for failures so trainers know what happened and how to recover.

## Failure scenarios
1. Camera unavailable / permission denied
2. Model missing / model load failure
3. BLE disconnect mid-run
4. No BLE telemetry after connect
5. Runtime performance degradation

## Locked Sprint BLE disconnect policy (confirmed)
- On disconnect during locked sprint:
  1. Pause run immediately.
  2. Show reconnect countdown (10 seconds).
  3. If reconnect succeeds within window -> resume.
  4. If reconnect fails -> auto-end run with reason `device_disconnect_timeout`.

## Standard failure UI format
- Title (what failed)
- Short cause summary
- Action buttons (Retry / Open Settings / Exit Run)
- Optional diagnostic details foldout

## Recovery actions matrix

### Camera failure
- Retry camera init
- Open Settings
- Exit to Hub

### Model load failure
- Retry load
- Enter diagnostics screen
- Exit to Hub

### BLE timeout/disconnect
- Retry connect
- Continue only in non-locked mode (if applicable)
- End run

## Logging behavior
- Store summary-level failure event in run/session summary.
- Avoid long-term raw trace storage in v1.
