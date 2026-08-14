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
    @State private var showingBlacklistedDevices = false
    @State private var showingDriverInstallConfirmation = false
    @State private var showingDriverUninstallConfirmation = false
   
    private let deviceRowHeight: CGFloat = 78
    private let maximumVisibleDeviceRows = 3

    private var deviceListHeight: CGFloat {
        let visibleRows = min(model.devices.count, maximumVisibleDeviceRows)
        return CGFloat(visibleRows) * deviceRowHeight
    }

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

                Text("Device Watcher")

                switch hostStatusModel.status {
                case .checking:
                    Text("Checking…")
                        .foregroundStyle(.secondary)
                case .starting:
                    Text("Starting…")
                        .foregroundStyle(.secondary)
                case .probablyUp:
                    if let lastChecked = hostStatusModel.lastChecked {
                            Text("Probably up — checked \(lastChecked.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Probably up")
                                .foregroundStyle(.secondary)
                        }
                case .notDetected:
                    Text("Not detected")
                        .foregroundStyle(.secondary)
                case .stopping:
                    Text("Stopping…")
                        .foregroundStyle(.secondary)
                case .stopped:
                    Text("Pretty sure it's stopped")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                switch hostStatusModel.status {
                case .checking:
                    EmptyView()

                case .probablyUp, .notDetected:
                    Button("Stop") {
                        hostStatusModel.stop()
                    }

                case .stopped:
                    Button("Start") {
                        hostStatusModel.start()
                    }
                case .starting:
                    Button("Starting…") {}
                        .disabled(true)
                case .stopping:
                    Button("Stopping…") {}
                        .disabled(true)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(driverStatusColor)
                    .frame(width: 9, height: 9)

                Text("Audio Driver")

                Text(driverStatusText)
                    .foregroundStyle(.secondary)

                Spacer()

                switch driverStatusModel.status {
                case .checking:
                    EmptyView()

                case .installed:
                    Button("Uninstall…") {
                        showingDriverUninstallConfirmation = true
                    }

                case .notInstalled:
                    Button("Install…") {
                        showingDriverInstallConfirmation = true
                    }
                }
            }

            HStack {
                Spacer()

                Button("Blacklisted Devices…") {
                    showingBlacklistedDevices = true
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 300)
        .sheet(isPresented: $showingBlacklistedDevices) {
           BlacklistedDevicesView(model: model)
        }
        .onAppear {
            hostStatusModel.refresh()
            driverStatusModel.refresh()
        }
        .confirmationDialog(
            "Uninstall Audio Driver?",
            isPresented: $showingDriverUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                driverStatusModel.uninstall()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "SoundFridge will remove its audio driver and restart Core Audio. " +
                "Audio playback may be interrupted briefly."
            )
        }
        .confirmationDialog(
            "Install Audio Driver?",
            isPresented: $showingDriverInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Install") {
                driverStatusModel.install()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "SoundFridge needs to install its audio driver to provide volume control. " +
                "Installing it will restart Core Audio, which may briefly interrupt playback."
            )
        }
        .alert(
            "Audio Driver Operation Failed",
            isPresented: Binding(
                get: { driverStatusModel.operationError != nil },
                set: { isPresented in
                    if !isPresented {
                        driverStatusModel.clearOperationError()
                    }
                }
            )
        ) {
            Button("OK") {
                driverStatusModel.clearOperationError()
            }
        } message: {
            Text(driverStatusModel.operationError ?? "Unknown error.")
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
        .frame(height: deviceListHeight)
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
        Removing \(device.name) makes SoundFridge forget this device. If it is connected again, SoundFridge may detect it as a new device.

        Blacklist the device instead if you do not want SoundFridge to show it again.
        """
    }

    private var hostStatusColor: Color {
        switch hostStatusModel.status {
        case .checking, .starting, .stopping:
            return .gray
        case .probablyUp:
            return .green
        case .notDetected:
            return .yellow
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
