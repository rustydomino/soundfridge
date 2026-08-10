import SwiftUI

/// Displays devices that SoundFridge has been told to ignore permanently.
///
/// Blocked devices remain in the registry so the Host can recognize their
/// stable UIDs, but they do not appear in the normal device list.
struct BlockedDevicesView: View {
    @ObservedObject var model: DeviceConfigurationModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Blocked Devices")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(
                    "Blocked devices are ignored by SoundFridge and will not "
                        + "appear as new-device prompts."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if model.blockedDevices.isEmpty {
                VStack {
                    Spacer()

                    Text("No blocked devices.")
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.blockedDevices) { device in
                    HStack {
                        Text(device.name)

                        Spacer()

                        Button("Unblock") {
                            model.unblockDevice(device.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                if !model.blockedDevices.isEmpty {
                    Button("Clear All", role: .destructive) {
                        showingClearAllConfirmation = true
                    }
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 320)
        .confirmationDialog(
            "Unblock all devices?",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unblock All", role: .destructive) {
                model.clearBlacklist()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All blocked devices will return to SoundFridge’s normal "
                    + "device enrollment list."
            )
        }
    }
}
