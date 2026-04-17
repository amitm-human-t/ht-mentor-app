import Foundation
import simd

/// Simulator stand-in for `HandXBLEManager`.
/// Starts in `.connected` state and slowly animates sample values so UI that
/// reads `latestSample` (orientation rings, joystick readouts) behaves
/// realistically in the simulator without any real BLE hardware.
@MainActor
@Observable
final class MockHandXBLEManager: HandXBLEProvider {

    private(set) var connectionState: HandXBLEManager.ConnectionState = .connected
    private(set) var discoveredDevices: [DiscoveredHandXDevice] = []
    private(set) var latestSample: HandXSample = .zero.markConnected()
    private(set) var statusText: String = "Mock HandX — Connected"

    @ObservationIgnored private var animationTask: Task<Void, Never>?
    @ObservationIgnored private var phase: Double = 0

    init() {
        startAnimation()
    }

    // MARK: - HandXBLEProvider

    func startScan() {
        connectionState = .scanning
        statusText = "Mock — Scanning"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            connectionState = .connected
            statusText = "Mock HandX — Connected"
            startAnimation()
        }
    }

    func stopScan() {
        if connectionState == .scanning {
            connectionState = .disconnected
            statusText = "Mock — Scan stopped"
        }
    }

    func connect(to device: DiscoveredHandXDevice) {
        connectionState = .connecting
        statusText = "Mock — Connecting"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            connectionState = .connected
            statusText = "Mock HandX — Connected"
            startAnimation()
        }
    }

    func disconnect() {
        animationTask?.cancel()
        connectionState = .disconnected
        latestSample = latestSample.markDisconnected()
        statusText = "Mock — Disconnected"
    }

    // MARK: - Simulation

    /// Slowly oscillates orientation, joystick, and grip so every live-data
    /// readout in the UI has something to display in the simulator.
    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.phase += 0.04
                let t = self.phase
                self.latestSample = HandXSample(
                    timestamp: Date().timeIntervalSince1970,
                    connected: true,
                    joystick: SIMD2(
                        Float(sin(t) * 0.6),
                        Float(cos(t * 0.7) * 0.4)
                    ),
                    direction: Float(sin(t * 0.5) * 180),
                    bend: Float((sin(t * 0.3) + 1) * 0.5),
                    roll: Float(sin(t * 0.4) * 90),
                    grip: Float((cos(t * 0.6) + 1) * 0.5),
                    orientation: SIMD3(
                        Float(sin(t * 0.5) * 30),
                        Float(cos(t * 0.4) * 20),
                        Float(sin(t * 0.3) * 45)
                    ),
                    state: ["lock": Int((sin(t) > 0.7) ? 1 : 0), "sys": 1],
                    buttons: .init(event: [], number: [], state: [])
                )
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
