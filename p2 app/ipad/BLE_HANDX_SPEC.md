# HandX BLE Spec for iPad

## Goal
Implement reliable HandX BLE connectivity and normalized input delivery for task engines on iPad.

## BLE responsibilities
1. Discover and connect to HandX dongle/device.
2. Subscribe to fast + slow telemetry characteristics.
3. Decode packets into normalized app-level sample.
4. Expose connection state and latest sample to runner.
5. Gate HandX-required modes (Locked Sprint).

## BLE packet fields to preserve
- orientation: `roll`, `pitch`, `yaw`
- joystick channels: `joy_x`, `joy_y`, plus direction/bend if available
- finger-unit channels: `roll`, `grip`
- state flags: system/lock/coupling/invert modes
- button data: events, state, counters

## Recommended iOS components
- `CBCentralManager` for scan/connect lifecycle
- `CBPeripheral` notifications for data characteristics
- dedicated `HandXPacketDecoder` for byte-level parsing
- `HandXInputProvider` for normalized output consumed by runner

## App-level data contract
```swift
struct HandXSample {
  var timestamp: TimeInterval
  var connected: Bool
  var joystick: SIMD2<Float>
  var direction: Float
  var bend: Float
  var roll: Float
  var grip: Float
  var orientation: SIMD3<Float> // roll, pitch, yaw
  var state: [String: Int]
  var buttons: [String: Int]
}
```

## State machine
- `disconnected`
- `scanning`
- `connecting`
- `connected`
- `error`

## Locked Sprint gating
- KeyLock + Tip Positioning locked sprint buttons disabled unless BLE state is `connected`.
- If BLE disconnects during run:
  - pause and show warning, or
  - end run with explicit reason (team decision in implementation)

## Reliability requirements
- Debounced reconnect attempts.
- Clear user-visible status (connecting/connected/disconnected).
- Timeout handling for no telemetry after connect.

## Dev/testing support
- Keep a mock provider path in app architecture for simulator/testing mode.
- Include packet replay capability (optional) for deterministic BLE regression checks.

## Privacy and data handling
- Do not persist raw BLE stream long-term in v1.
- Use BLE data only for:
  - live task control
  - temporary session metrics
  - summarized per-run stats
