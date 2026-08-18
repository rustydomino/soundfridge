//
// Original prompt: Add the SoundFridge onboarding device-discovery screen
// using the existing device registry and pending-device state.
// Date: 2026-08-14
//
// Used by the SoundFridge GUI.
// Test by building the SoundFridge target in Xcode with Command-B.
//

import SwiftUI

struct OnboardingDeviceDiscoveryView: View {
    @ObservedObject var model: DeviceConfigurationModel

    let onManage: (DeviceConfigurationRow) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Choose Your Audio Devices")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(
                    "SoundFridge can manage compatible audio devices " +
                    "that do not provide their own macOS volume control."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 430)

            deviceContent

            Spacer()

            HStack {
                Spacer()

                Button("Continue") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 520, height: 360)
        .onAppear {
            model.reload()
        }
    }

    @ViewBuilder
    private var deviceContent: some View {
        if !model.connectedPendingDevices.isEmpty {
            VStack(spacing: 12) {
                ForEach(model.connectedPendingDevices) { device in
                    HStack {
                        Text(device.name)

                        Spacer()

                        Button("Manage") {
                            onManage(device)
                        }
                    }
                }
            }
            .frame(maxWidth: 400)

        } else if model.connectedDevices.isEmpty {
            VStack(spacing: 8) {
                Text("No compatible devices are connected right now.")
                    .font(.headline)

                if model.devices.isEmpty {
                    Text(
                        "SoundFridge will notice eligible devices when " +
                        "you connect them later."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        "Your previously configured devices will be available " +
                        "when you reconnect them."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 400)

        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .accessibilityHidden(true)

                Text("Your connected devices are already configured.")
                    .font(.headline)
            }
        }
    }
}
