import CoreBluetooth
import Foundation
import simd


@MainActor
@Observable
final class HandXBLEManager: NSObject {
    enum ConnectionState: String {
        case disconnected
        case scanning
        case connecting
        case connected
        case error
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredDevices: [DiscoveredHandXDevice] = []
    private(set) var latestSample = HandXSample.zero
    private(set) var statusText = "Disconnected"

    private let serviceUUID = CBUUID(string: "DD90EC52-0000-4357-891A-26D580F709EF")
    private let fastUUID = CBUUID(string: "DD90EC52-2001-4357-891A-26D580F709EF")
    private let slowUUID = CBUUID(string: "DD90EC52-2002-4357-891A-26D580F709EF")
    private let legacyUUID = CBUUID(string: "DD90EC52-1002-4357-891A-26D580F709EF")

    @ObservationIgnored
    private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    @ObservationIgnored
    private var connectedPeripheral: CBPeripheral?
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusText = "Bluetooth unavailable"
            connectionState = .error
            return
        }
        discoveredDevices = []
        connectionState = .scanning
        statusText = "Scanning for HandX"
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
            statusText = "Scan stopped"
        }
    }

    func connect(to device: DiscoveredHandXDevice) {
        guard connectionState != .connecting else { return }
        stopScan()
        connectionState = .connecting
        statusText = "Connecting to \(device.name)"
        connectedPeripheral = device.peripheral
        device.peripheral.delegate = self
        centralManager.connect(device.peripheral)
    }

    func disconnect() {
        reconnectTask?.cancel()
        guard let connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(connectedPeripheral)
    }

    private func handleDisconnect() {
        latestSample = latestSample.markDisconnected()
        connectionState = .disconnected
        statusText = "Disconnected"
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard let connectedPeripheral else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.connectionState == .disconnected else { return }
            await MainActor.run {
                self.connectionState = .connecting
                self.statusText = "Reconnecting"
                self.centralManager.connect(connectedPeripheral)
            }
        }
    }
}

extension HandXBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            connectionState = .error
            statusText = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let normalizedName = name.replacingOccurrences(of: " ", with: "").lowercased()
        let isHandX = normalizedName.contains("handx") || normalizedName.contains("hxdongle") || serviceUUIDs.contains(fastUUID) || serviceUUIDs.contains(slowUUID) || serviceUUIDs.contains(serviceUUID)
        guard isHandX else { return }

        let device = DiscoveredHandXDevice(id: peripheral.identifier, name: name, peripheral: peripheral, rssi: RSSI.intValue)
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        statusText = "Connected"
        latestSample = latestSample.markConnected()
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDisconnect()
        scheduleReconnect()
    }
}

extension HandXBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([fastUUID, slowUUID, legacyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where [fastUUID, slowUUID, legacyUUID].contains(characteristic.uuid) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == fastUUID {
            latestSample = HandXPacketDecoder.mergeFastPacket(data, onto: latestSample.markConnected())
        } else if characteristic.uuid == slowUUID || characteristic.uuid == legacyUUID {
            latestSample = HandXPacketDecoder.mergeSlowPacket(data, onto: latestSample.markConnected())
        }
    }
}

struct DiscoveredHandXDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    let rssi: Int

    static func == (lhs: DiscoveredHandXDevice, rhs: DiscoveredHandXDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
