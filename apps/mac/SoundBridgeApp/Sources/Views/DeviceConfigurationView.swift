import SwiftUI

/// Main SoundFridge device-configuration view.
///
/// This first version is intentionally read-only. It verifies that the GUI
/// can display the same persistent device registry used by the Host.
struct DeviceConfigurationView: View {
    @ObservedObject var model: DeviceConfigurationModel
    @ObservedObject var hostStatusModel: HostStatusModel
    @ObservedObject var driverStatusModel: DriverStatusModel

    @State private var devicePendingRemoval: DeviceConfigurationRow?
    @State private var showingBlockedDevices = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Devices Apple decided didn't need volume control")
                .font(.headline)

            if let loadError = model.loadError {
                errorView(loadError)
            } else if model.devices.isEmpty {
                emptyView
            } else {
                deviceList
            }

            if let saveError = model.saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("System")
                .font(.headline)

            HStack(spacing: 8) {
                Circle()
                    .fill(hostStatusColor)
                    .frame(width: 9, height: 9)

                Text("SoundFridge Service")

                Spacer()

                switch hostStatusModel.status {
                case .checking:
                    Text("Checking…")
                        .foregroundStyle(.secondary)

                case .running:
                    Text("Running")
                        .foregroundStyle(.secondary)

                    Button("Stop") {
                        hostStatusModel.stop()
                    }

                case .stopped:
                    Text("Stopped")
                        .foregroundStyle(.secondary)

                    Button("Start") {
                        hostStatusModel.start()
                    }
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(driverStatusColor)
                    .frame(width: 9, height: 9)

                Text("Audio Driver")

                Spacer()

                Text(driverStatusText)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button("Blocked Devices…") {
                    showingBlockedDevices = true
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 300)
        .sheet(isPresented: $showingBlockedDevices) {
           BlockedDevicesView(model: model)
        }
        .onAppear {
            hostStatusModel.refresh()
            driverStatusModel.refresh()
        }
    }

    private var deviceList: some View {
        List(model.devices) { device in
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name)
                        .font(.body)

                    Toggle(
                        "Give it volume control",
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
        .confirmationDialog(
            "Remove device?",
            isPresented: Binding(
                get: {
                    devicePendingRemoval != nil
                },
                set: { isPresented in
                    if !isPresented {
                        devicePendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: devicePendingRemoval
        ) { device in
            Button("Remove") {
                model.removeDevice(device.id)
            }

            Button("Blacklist Device", role: .destructive) {
                model.blacklistDevice(device.id)
            }

            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text(removalMessage(for: device))
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

    private func removalMessage(for device: DeviceConfigurationRow) -> String {
        """
        Remove \(device.name) to forget it. If it is connected again, SoundFridge may detect it as a new device.

        Blacklist the device to prevent SoundFridge from showing or prompting for it again.
        """
    }

    private var hostStatusColor: Color {
        switch hostStatusModel.status {
        case .checking:
            return .gray
        case .running:
            return .green
        case .stopped:
            return .red
        }
    }

    private var driverStatusText: String {
        switch driverStatusModel.status {
        case .checking:
            return "Checking…"
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not Installed"
        }
    }

    private var driverStatusColor: Color {
        switch driverStatusModel.status {
        case .checking:
            return .gray
        case .installed:
            return .green
        case .notInstalled:
            return .red
        }
    }

}
