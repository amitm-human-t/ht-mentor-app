import SwiftUI

struct PermissionCenterView: View {
    @ObservedObject var permissionCenter: PermissionCenter

    var body: some View {
        List {
            Section("Camera") {
                LabeledContent("Status", value: permissionCenter.snapshot.camera.rawValue)
                Button("Request Camera Access") {
                    Task {
                        await permissionCenter.requestCameraAccess()
                    }
                }
            }

            Section("Bluetooth") {
                LabeledContent("Status", value: permissionCenter.snapshot.bluetooth.rawValue)
                Button("Prime Bluetooth Prompt") {
                    permissionCenter.primeBluetoothPrompt()
                }
            }

            Section("Recovery") {
                Button("Open Settings") {
                    permissionCenter.openSettings()
                }
            }
        }
        .navigationTitle("Permissions")
    }
}
