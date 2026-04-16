# iOS Permissions + Privacy Keys Checklist (Xcode)

## Required permissions for v1
1. Camera access (rear camera live task feed)
2. Bluetooth access (HandX discovery + connection)

## Info.plist keys to define
- `NSCameraUsageDescription`
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription` (if needed for deployment target compatibility)

## Suggested permission copy (draft)
- Camera: "HandX Training Hub uses the rear camera to detect task elements and render real-time training overlays."
- Bluetooth: "HandX Training Hub uses Bluetooth to connect to the HandX device for task control and telemetry."

## Permission UX flow
1. Show pre-permission explainer screen before system prompt.
2. Trigger system prompt only when user initiates relevant action.
3. If denied, show clear settings deep-link guidance.

## Denial handling requirements
- Camera denied:
  - Block TaskRunner start.
  - Show recovery UI with "Open Settings" action.
- Bluetooth denied:
  - Disable locked sprint modes and HandX-only features.
  - Allow non-HandX modes to continue where possible.

## Data/privacy commitments reflected in product messaging
- No session video recording in v1.
- Raw session telemetry is transient and pruned after summary extraction.
- Summary-level training outcomes and user progress are stored locally.

## QA checklist
- [ ] Fresh install permission flow validated
- [ ] Denied permission recovery path validated
- [ ] Settings re-enable flow validated
- [ ] Copy text approved by product/legal stakeholders
