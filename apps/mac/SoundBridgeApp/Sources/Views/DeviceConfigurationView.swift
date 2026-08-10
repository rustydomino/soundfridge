import SwiftUI

/// Main SoundFridge device-configuration view.
///
/// This first version is intentionally read-only. It verifies that the GUI
/// can display the same persistent device registry used by the Host.
struct DeviceConfigurationView: View {
    @ObservedObject var model: DeviceConfigurationModel
    @State private var devicePendingRemoval: DeviceConfigurationRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SoundFridge")
                .font(.title)
                .fontWeight(.semibold)

            Text("Volume Control")
                .font(.headline)

            if let loadError = model.loadError {
                errorView(loadError)
            } else if model.devices.isEmpty {
                emptyView
            } else {
                deviceList
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 300)
    }

    private var deviceList: some View {
        List(model.devices) { device in
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name)
                        .font(.body)

                    Toggle(
                        "Master volume control",
                        isOn: Binding(
                            get: {
                                device.decision == .managed
                            },
                            set: { enabled in
                                model.setVolumeControlEnabled(
                                    enabled,
                                    for: device.id
                                )
                            }
                        )
                    )
                    .disabled(device.decision == .pending)
                }

                Spacer()

                if device.decision == .pending {
                    Button("Manage") {
                        model.setVolumeControlEnabled(true, for: device.id)
                    }
                } else {
                    Button("Remove") {
                        devicePendingRemoval = device
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .alert(item: $devicePendingRemoval) { device in
            Alert(
                title: Text("Remove \(device.name) from SoundFridge?"),
                message: Text(
                    "This forgets the device and removes it from SoundFridge’s device list. "
                        + "If the device is still connected and compatible, SoundFridge may "
                        + "detect it again as a new device."
                ),
                primaryButton: .destructive(Text("Remove")) {
                    model.removeDevice(device.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()

            Text("No compatible devices found")
                .font(.headline)

            Text("SoundFridge will show devices here when they are available for volume control.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()

            Text("Unable to Load Devices")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func statusText(for decision: DeviceDecision) -> String {
        switch decision {
        case .pending:
            return "Needs configuration"
        case .managed:
            return "Volume control on"
        case .ignored:
            return "Volume control off"
        }
    }
}
