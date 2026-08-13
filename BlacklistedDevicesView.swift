import SwiftUI

/// Displays devices that SoundFridge has been told to ignore permanently.
///
/// Blacklisted devices remain in the registry so the Host can recognize their
/// stable UIDs, but they do not appear in the normal device list.
struct BlacklisteDevicesView: View {
    @ObservedObject var model: DeviceConfigurationModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Blacklisted Devices")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(
                    "Blacklisted devices are ignored by SoundFridge and will not "
                        + "appear as new-device prompts."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if model.blacklistedDevices.isEmpty {
                VStack {
                    Spacer()

                    Text("No blacklisted devices.")
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.blacklistedDevices) { device in
                    HStack {
                        Text(device.name)

                        Spacer()

                        Button("Remove from Blacklist") {
                            model.removeFromBlacklist(device.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                if !model.blacklistedDevices.isEmpty {
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
            "Remove from Blacklist all devices?",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Blacklist All", role: .destructive) {
                model.clearBlacklist()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All blacklisted devices will return to SoundFridge’s normal "
                    + "device enrollment list."
            )
        }
    }
}
