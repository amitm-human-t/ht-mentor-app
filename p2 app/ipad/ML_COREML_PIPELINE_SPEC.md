# ML + CoreML Pipeline Spec (from Ultralytics YOLO)

## Goal
Replace desktop YOLO `.pt` inference with iPad-native CoreML inference while preserving task behavior and overlay semantics.

## v1 Models to ship

### Required runtime models
1. `models/keylock.pt`
2. `models/tippos.pt`
3. `models/rubberband.pt`
4. `models/springs.pt`
5. `new_models/instrument_tip/instrument_tip.pt` (always-on parallel tracker)

### Optional / not required for v1 parity
- `models/keylock_v2.pt` (only if KeyLock V2 is explicitly enabled in iPad roadmap)
- `models/tippos_hover.pt` (currently not referenced by active task manifests)
- legacy `models/old models/*`
- `new_models/keylock_new/*`

## Conversion pipeline (recommended)

## 1) Export to CoreML
Use Ultralytics export from the same training environment used for desktop validation.

Example commands:
```bash
python -m ultralytics export model=models/keylock.pt format=coreml imgsz=640 nms=True
python -m ultralytics export model=models/tippos.pt format=coreml imgsz=640 nms=True
python -m ultralytics export model=models/rubberband.pt format=coreml imgsz=640 nms=True
python -m ultralytics export model=models/springs.pt format=coreml imgsz=640 nms=True
python -m ultralytics export model=new_models/instrument_tip/instrument_tip.pt format=coreml imgsz=640 nms=True
```

## 2) Normalize metadata
For each converted model, persist metadata in `model_manifest.json` adjacent to model asset:
- source `.pt` path
- class-name mapping (`id -> label`)
- input size / preprocessing details
- confidence and IoU defaults

## 3) Validate parity
Run offline validation clips and compare:
- detection presence/absence parity
- class label parity
- rough bbox IoU parity
- no class-index drift

## 4) Integrate into Xcode
- Add models to `Resources/Models/`.
- Compile into `.mlmodelc` at build time.
- Load with a shared `CoreMLModelRegistry`.

## Runtime inference architecture

## Task inference worker
- One active task model per run.
- Runs per-frame detections asynchronously.
- Produces lightweight detection payload for task engine.

## Instrument inference worker
- Separate worker for instrument model.
- Runs in parallel and writes latest tip payload.
- Applies short TTL smoothing (e.g., 300–500ms) to avoid flicker.

## Merge in coordinator
- `RunnerCoordinator` merges task detections + instrument detections + BLE sample.
- Invokes task engine step.

## Recommended model runtime knobs (initial)
- Confidence threshold per task configurable in trainer debug settings.
- IoU threshold per task configurable.
- Max detections per frame per model configurable.

## Frame handling rules
- Use frame dropping over deep queueing when under load.
- Maintain latest-frame semantics for responsiveness.
- Never block UI thread on model prediction.

## CoreML + Vision implementation notes
- Preferred path:
  - `AVCaptureVideoDataOutput` -> `CVPixelBuffer`
  - `VNCoreMLRequest` or direct CoreML model invocation (team choice)
- If using Vision, ensure coordinate transforms are centrally handled and tested against overlay renderer.

## Model QA checklist
- [ ] Each model loads successfully on target iPad hardware
- [ ] Class maps exactly match desktop manifests
- [ ] Expected targets detected in baseline scenes
- [ ] Overlay alignment confirmed (bbox positions correct)
- [ ] End-to-end FPS acceptable with task + instrument models running together
