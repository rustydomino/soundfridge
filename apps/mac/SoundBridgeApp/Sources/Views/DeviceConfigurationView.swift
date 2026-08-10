import SwiftUI

/// Main SoundFridge device-configuration view.
///
/// This first version is intentionally read-only. It verifies that the GUI
/// can display the same persistent device registry used by the Host.
struct DeviceConfigurationView: View {
    @ObservedObject var model: DeviceConfigurationModel

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.body)

                    Text(device.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                switch device.decision {
                case .pending:
                    HStack {
                        Button("Enable") {
                            model.setVolumeControlEnabled(true, for: device.id)
                        }

                        Button("Ignore") {
                            model.setVolumeControlEnabled(false, for: device.id)
                        }
                    }

                case .managed:
                    Button("Turn Off") {
                        model.setVolumeControlEnabled(false, for: device.id)
                    }

                case .ignored:
                    Button("Turn On") {
                        model.setVolumeControlEnabled(true, for: device.id)
                    }
                }
            }
            .padding(.vertical, 4)
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
