# Xcode Asset Migration Checklist (Models + Sounds + Graphics)

This file lists the concrete assets that should be copied from this repo into the iPad Xcode project.

## 1) Models required for v1

Copy these exact source files:

1. `models/keylock.pt`
2. `models/tippos.pt`
3. `models/rubberband.pt`
4. `models/springs.pt`
5. `new_models/instrument_tip/instrument_tip.pt`

Recommended Xcode destination:
- `HandXPad/Resources/Models/pt/`

Recommended converted CoreML destination:
- `HandXPad/Resources/Models/coreml/`

## 2) Models currently optional / excluded for v1 parity

- `models/keylock_v2.pt` (only include if KeyLock V2 is explicitly in iPad roadmap)
- `models/tippos_hover.pt` (not referenced by active task manifests)
- `models/instruments.pt` (not currently in active runtime manifests)
- `models/old models/*` (legacy only)
- `new_models/keylock_new/*` (research/training artifacts)

## 3) Sound assets required for v1

### Backgrounds
- `app/ui/sounds/backgrounds/background1.wav`
- `app/ui/sounds/backgrounds/background2.wav`

### Global effects
- `app/ui/sounds/effects/fail.wav`
- `app/ui/sounds/effects/finished.wav`
- `app/ui/sounds/effects/gameover.wav`
- `app/ui/sounds/effects/success.wav`
- `app/ui/sounds/effects/success2.wav`

### KeyLock callouts
- `app/ui/sounds/keylock/1.mp3`
- `app/ui/sounds/keylock/2.mp3`
- `app/ui/sounds/keylock/3.mp3`
- `app/ui/sounds/keylock/4.mp3`
- `app/ui/sounds/keylock/5.mp3`
- `app/ui/sounds/keylock/6.mp3`
- `app/ui/sounds/keylock/7.mp3`
- `app/ui/sounds/keylock/8.mp3`
- `app/ui/sounds/keylock/9.mp3`
- `app/ui/sounds/keylock/10.mp3`
- `app/ui/sounds/keylock/11.mp3`
- `app/ui/sounds/keylock/12.mp3`
- `app/ui/sounds/keylock/13.mp3`

### Tip Positioning callouts
- `app/ui/sounds/tip_positioning/l1.mp3`
- `app/ui/sounds/tip_positioning/l2.mp3`
- `app/ui/sounds/tip_positioning/l3.mp3`
- `app/ui/sounds/tip_positioning/l4.mp3`
- `app/ui/sounds/tip_positioning/l5.mp3`
- `app/ui/sounds/tip_positioning/l6.mp3`
- `app/ui/sounds/tip_positioning/l7.mp3`
- `app/ui/sounds/tip_positioning/r1.mp3`
- `app/ui/sounds/tip_positioning/r2.mp3`
- `app/ui/sounds/tip_positioning/r3.mp3`
- `app/ui/sounds/tip_positioning/r4.mp3`
- `app/ui/sounds/tip_positioning/r5.mp3`
- `app/ui/sounds/tip_positioning/r6.mp3`
- `app/ui/sounds/tip_positioning/r7.mp3`

Recommended Xcode destination:
- `HandXPad/Resources/Sounds/backgrounds/`
- `HandXPad/Resources/Sounds/effects/`
- `HandXPad/Resources/Sounds/keylock/`
- `HandXPad/Resources/Sounds/tip_positioning/`

## 4) Graphics / icon assets to migrate

Copy:
- `app/ui/resources/icons/pause.png`
- `app/ui/resources/icons/play.png`
- `app/ui/resources/icons/points.png`
- `app/ui/resources/icons/skip1.png`
- `app/ui/resources/icons/skip5.png`
- `app/ui/resources/icons/target.png`
- `app/ui/resources/icons/time.png`
- `app/ui/resources/icons/video.png`
- `app/ui/resources/icons/video_slash.png`

Recommended destination:
- Xcode Asset Catalog (`Assets.xcassets`) with semantic names matching usage.

## 5) Migration procedure
1. Copy raw `.pt` and media assets into Xcode resource tree.
2. Convert required `.pt` files to CoreML (`.mlmodel`) and integrate into build.
3. Validate file presence at startup with a startup asset check.
4. Fail fast (developer build) or show friendly missing-asset screen (release build).

## 6) Runtime asset contract
- Keep a central Swift `AssetCatalog` enum listing every model/sound/icon key.
- Do not hardcode scattered string paths in feature code.
- Add a startup diagnostics screen/log that reports missing model or sound assets.
