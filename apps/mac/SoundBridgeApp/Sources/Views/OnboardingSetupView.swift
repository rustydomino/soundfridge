//
// Original prompt: Add the SoundFridge onboarding screen that installs and
// reports the required audio driver and background Device Watcher components.
// Date: 2026-08-14
//
// Used by the SoundFridge GUI.
// Test by building the SoundFridge target in Xcode with Command-B.
//

import SwiftUI

struct OnboardingSetupView: View {
    @ObservedObject var driverStatusModel: DriverStatusModel
    @ObservedObject var hostStatusModel: HostStatusModel

    let onContinue: () -> Void

    private var driverInstalled: Bool {
        driverStatusModel.status == .installed
    }

    private var deviceWatcherRunning: Bool {
        hostStatusModel.status == .probablyUp
    }

    private var setupReady: Bool {
        driverInstalled && deviceWatcherRunning
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Set Up SoundFridge")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(
                    "SoundFridge needs its audio driver and background Device Watcher " +
                    "enabled before it can control your audio devices."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 430)

            VStack(spacing: 14) {
                componentRow(
                    name: "Audio Driver",
                    status: driverStatusText,
                    ready: driverInstalled
                )

                componentRow(
                    name: "Device Watcher",
                    status: deviceWatcherStatusText,
                    ready: deviceWatcherRunning
                )
            }
            .frame(maxWidth: 400)

            if let error = driverStatusModel.operationError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                if !setupReady {
                    Button("Set Up") {
                        setUpSoundFridge()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Spacer()

                if setupReady {
                    Button("Continue") {
                        onContinue()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(width: 520, height: 360)
        .onAppear {
            driverStatusModel.refresh()
            hostStatusModel.refresh()
        }
    }

    @ViewBuilder
    private func componentRow(
        name: String,
        status: String,
        ready: Bool
    ) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .accessibilityHidden(true)

            Text(name)

            Spacer()

            Text(status)
                .foregroundStyle(.secondary)
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

    private var deviceWatcherStatusText: String {
        switch hostStatusModel.status {
        case .checking:
            return "Checking…"

        case .starting:
            return "Enabling…"

        case .probablyUp:
            return "Running"

        case .notDetected:
            return "Enabled, Not Running"

        case .stopping:
            return "Disabling…"

        case .stopped:
            return "Not Enabled"
        }
    }

    private func setUpSoundFridge() {
        driverStatusModel.clearOperationError()

        if !driverInstalled {
            driverStatusModel.install()
        }

        if !deviceWatcherRunning {
            hostStatusModel.start()
        }
    }
}
