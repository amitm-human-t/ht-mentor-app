import SwiftUI

struct BLEConsoleView: View {
    @ObservedObject var bleManager: HandXBLEManager

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("State", value: bleManager.connectionState.rawValue)
                LabeledContent("Status", value: bleManager.statusText)
                HStack {
                    Button("Scan") {
                        bleManager.startScan()
                    }
                    Button("Disconnect") {
                        bleManager.disconnect()
                    }
                }
            }

            Section("Devices") {
                ForEach(bleManager.discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("RSSI \(device.rssi)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            bleManager.connect(to: device)
                        }
                    }
                }
            }

            Section("Latest Sample") {
                LabeledContent("Connected", value: bleManager.latestSample.connected ? "Yes" : "No")
                LabeledContent("Joystick", value: "\(bleManager.latestSample.joystick.x.formatted(.number.precision(.fractionLength(2)))), \(bleManager.latestSample.joystick.y.formatted(.number.precision(.fractionLength(2))))")
                LabeledContent("Orientation", value: "\(Int(bleManager.latestSample.orientation.x)), \(Int(bleManager.latestSample.orientation.y)), \(Int(bleManager.latestSample.orientation.z))")
            }
        }
        .navigationTitle("HandX BLE")
    }
}
