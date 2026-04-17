# CoreBluetooth / HandX BLE — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:core-bluetooth`
**Use when:** BLE scanning, disconnect policy, HandX data, MockHandXBLEManager.

---

## HandXBLEProvider Protocol (Core/BLE/HandXBLEProvider.swift)

```swift
protocol HandXBLEProvider: AnyObject {
    var connectionState: HandXBLEManager.ConnectionState { get }
    var discoveredDevices: [HandXDevice] { get }
    var latestSample: HandXSample { get }
    var statusText: String { get }

    func startScan()
    func stopScan()
    func connect(to device: HandXDevice)
    func disconnect()
}
```

## Concrete Implementations

| Class | File | Purpose |
|-------|------|---------|
| `HandXBLEManager` | `Core/BLE/HandXBLEManager.swift` | Real device (CBCentralManager) |
| `MockHandXBLEManager` | `Core/BLE/MockHandXBLEManager.swift` | Simulator (animating fake data) |

**Injection (AppModel.swift):**
```swift
#if targetEnvironment(simulator)
let bleManager: any HandXBLEProvider = MockHandXBLEManager()
#else
let bleManager: any HandXBLEProvider = HandXBLEManager()
#endif
```

## HandX BLE Service UUID

```
DD90EC52-0000-4357-891A-26D580F709EF
```

## HandXSample (the data packet)

```swift
struct HandXSample {
    var connected: Bool
    var joystick: SIMD2<Float>          // x, y — each -1.0…1.0
    var orientation: SIMD3<Float>       // x°, y°, z° (degrees)
    var grip: Float                     // 0.0…1.0
    var state: [String: Int]            // e.g. ["lock": 0/1]
}
```

## Disconnect Policy (RunnerCoordinator)

Only active in `.lockedSprint` mode. Flow:
1. `tick()` detects `bleManager.connectionState != .connected`
2. Calls `handleBLEDisconnect()`:
   - Calls `pause()`
   - Sets `disconnectCountdown = 10`
   - Starts background `Task` counting down 1 per second
3. Reconnect detected → `handleBLEReconnect()` → cancels countdown → `resume()`
4. Countdown hits 0 → `finish()` with `currentFailure = .bleDisconnectTimeout`

## BLEReconnectOverlay

Shown when `runnerCoordinator.disconnectCountdown != nil`:

```swift
// In TaskRunnerView
.overlay {
    if let countdown = runnerCoordinator.disconnectCountdown {
        BLEReconnectOverlay(countdown: countdown) {
            runnerCoordinator.finish()
        }
    }
}
```

## Entitlements Required (handled by human in Xcode)

- `NSBluetoothAlwaysUsageDescription` in `Info.plist`
- `com.apple.developer.bluetooth.background-scan` entitlement if background scanning needed

## Connection State Colors (Design Tokens)

```swift
switch bleManager.connectionState {
case .connected:          Color.hxSuccess
case .scanning, .connecting: Color.hxAmber
case .disconnected, .error:  Color.hxDanger
}
```
