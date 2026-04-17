import AVFoundation
import CoreBluetooth
import Foundation
import UIKit


@MainActor
@Observable
final class PermissionCenter: NSObject {
    private(set) var snapshot = PermissionSnapshot(camera: .notDetermined, bluetooth: .notDetermined)

    private var bluetoothProbe: CBCentralManager?

    func refresh() async -> PermissionSnapshot {
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        let bluetooth = PermissionStatus.fromBluetoothAuthorization(CBManager.authorization)
        let snapshot = PermissionSnapshot(
            camera: PermissionStatus.fromAVAuthorization(camera),
            bluetooth: bluetooth
        )
        self.snapshot = snapshot
        return snapshot
    }

    func requestCameraAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await refresh()
    }

    func primeBluetoothPrompt() {
        guard bluetoothProbe == nil else { return }
        bluetoothProbe = CBCentralManager(delegate: self, queue: nil)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension PermissionCenter: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            _ = await refresh()
        }
    }
}

struct PermissionSnapshot: Equatable {
    let camera: PermissionStatus
    let bluetooth: PermissionStatus
}

enum PermissionStatus: String, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unsupported

    static func fromAVAuthorization(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
    }

    static func fromBluetoothAuthorization(_ status: CBManagerAuthorization) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .allowedAlways:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
    }
}
