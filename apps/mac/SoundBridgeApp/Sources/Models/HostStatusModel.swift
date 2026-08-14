//
// Original prompt: Show whether the SoundFridge Host is running, including
// a green/red status indicator in the configuration GUI.
// Date: 2026-08-10
//
// Used automatically by the SoundFridge GUI. Build/test with:
//   swift build --package-path apps/mac/SoundBridgeApp
//

import Foundation
import Combine
import ServiceManagement

/// Current observed state of the SoundFridge background Host.
enum HostStatus {
    case checking
    case starting
    case probablyUp
    case notDetected
    case stopping
    case stopped
}

/// Observes and controls the independent SoundFridge Host service.
@MainActor
final class HostStatusModel: ObservableObject {
    @Published private(set) var status: HostStatus = .checking
    @Published private(set) var lastChecked: Date?

    private let servicePlistName = "com.soundbridge.host.plist"

    private var service: SMAppService {
        SMAppService.agent(plistName: servicePlistName)
    }

    /// Refresh the current Host process status.
    func refresh() {
        lastChecked = Date()

        if isHostRunning() {
            status = .probablyUp
        } else if isServiceLoaded() {
            status = .notDetected
        } else {
            status = .stopped
        }
    }

    /// Register the bundled Host service with macOS.
    func start() {
        status = .starting

        Task { @MainActor in
            do {
                switch service.status {
                case .notRegistered, .notFound:
                    try service.register()

                case .enabled:
                    break

                case .requiresApproval:
                    print("[HostStatus] Host service requires user approval")

                @unknown default:
                    print("[HostStatus] Unknown Host service status")
                }
            } catch {
                print("[HostStatus] Failed to register Host service: \(error)")
            }

            await waitForHostToStart()
            refresh()
        }
    }

    /// Unregister and stop the bundled SoundFridge Host service.
    func stop() {
        status = .stopping

        Task { @MainActor in
            do {
                switch service.status {
                case .enabled, .requiresApproval:
                    try await service.unregister()

                case .notRegistered, .notFound:
                    break

                @unknown default:
                    print("[HostStatus] Unknown Host service status")
                }
            } catch {
                print("[HostStatus] Failed to unregister Host service: \(error)")
            }

            await waitForHostToStop()
            refresh()
        }
    }

    private func isHostRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "SoundBridgeHost"]

        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[HostStatus] Failed to check Host process: \(error)")
            return false
        }
    }

    /// Check whether macOS knows about the bundled Host service.
    ///
    /// An enabled service is registered and available to run. A service that
    /// requires approval is also registered, but macOS is waiting for the user
    /// to allow its background activity.
    private func isServiceLoaded() -> Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            return true

        case .notRegistered, .notFound:
            return false

        @unknown default:
            return false
        }
    }

    /// Give launchd a short time to start the Host after registration.
    private func waitForHostToStart() async {
        for _ in 0..<20 {
            if isHostRunning() {
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Give the Host a short time to exit after unregistering the service.
    private func waitForHostToStop() async {
        for _ in 0..<20 {
            if !isHostRunning() {
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
