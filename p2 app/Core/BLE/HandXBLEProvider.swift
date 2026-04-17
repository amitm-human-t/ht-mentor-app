import Foundation

/// Protocol that abstracts the HandX BLE manager.
/// Both the real `HandXBLEManager` and `MockHandXBLEManager` conform to this.
/// `RunnerCoordinator` and all UI code depend on this protocol — never directly on the class.
@MainActor
protocol HandXBLEProvider: AnyObject, Observable {
    var connectionState: HandXBLEManager.ConnectionState { get }
    var discoveredDevices: [DiscoveredHandXDevice] { get }
    var latestSample: HandXSample { get }
    var statusText: String { get }

    func startScan()
    func stopScan()
    func connect(to device: DiscoveredHandXDevice)
    func disconnect()
}
