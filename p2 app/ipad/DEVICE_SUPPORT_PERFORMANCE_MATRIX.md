# Device Support + Performance Matrix (iPad v1)

## Confirmed minimum support target
- **Supported for v1:** iPad Pro with Apple Silicon (**M1 / M2 / M4**)
- **Out of scope for v1:** non-Pro iPads and pre-M1 devices

## Rationale
- Dual-model runtime (task model + always-on instrument model) requires sustained inference performance.
- Trainer UX requires stable low-latency camera + overlay pipeline.
- BLE + inference + overlay + session logic together are smoother on M-series iPad Pro hardware.

## Recommended baseline test devices
1. iPad Pro 11" (M1)
2. iPad Pro 12.9" (M2)
3. iPad Pro 13" (M4)

## Target runtime expectations
- Perceived smoothness target: 30 FPS+ during active runs
- Acceptable temporary dips: short bursts under heavy scene changes
- Must avoid sustained UI stutter or input lag

## Performance tiers (internal QA)
- **Tier A (ideal):** 40+ FPS equivalent responsiveness
- **Tier B (acceptable):** 30–40 FPS equivalent responsiveness
- **Tier C (investigate):** <30 FPS sustained for >10 seconds

## Required profiling scenarios
1. KeyLock locked sprint with HandX connected
2. Tip Positioning locked sprint with dense detections
3. Rubber Band with high motion/occlusion
4. Springs Suturing with complex loops/poles
5. Long session endurance (10+ minutes)

## Thermal and battery checks
- Confirm no severe thermal throttling under typical clinic/training session durations.
- Warn user if thermal state degrades inference responsiveness.

## Failure criteria for release block
- Reproducible frame stalls
- Reproducible delayed touch response in TaskRunner
- BLE/input lag caused by inference saturation
