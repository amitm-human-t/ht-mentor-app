# Calibration + Setup Flow (Pre-run)

## Goal
Provide a repeatable setup flow so sessions start with consistent camera framing, lighting, and HandX readiness.

## First-launch setup wizard (recommended)
1. Permission checks (camera + bluetooth)
2. Camera framing guide
3. Lighting quality check
4. HandX pairing + telemetry check
5. Quick model/inference readiness check

## Camera framing baseline
- Rear camera only.
- Show on-screen board alignment frame.
- Require target board occupying expected region before enabling "Continue".

## Lighting baseline
- Detect underexposure/overexposure risk from sample frames.
- Prompt trainer to adjust room/task lighting if threshold fails.

## HandX readiness check
- Confirm BLE connected.
- Confirm live packet updates (not stale).
- Confirm joystick + grip + orientation channels are updating.

## Pre-run health panel
Display clear green/yellow/red state for:
- Camera
- Model runtime
- HandX connection
- Frame rate/performance

## Run-start gating
- Allow run start only when required dependencies are healthy.
- For non-HandX modes, HandX can remain optional.

## Quick recalibration actions (in runner)
- Re-center board guide
- Recheck lighting
- Reconnect HandX
