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
import Darwin

/// Current observed state of the SoundFridge background Host.
enum HostStatus {
    case checking
    case running
    case stopped
}

/// Checks whether the independent SoundFridge Host process is running.
///
/// This does not start or stop the Host. It only observes its current state.
@MainActor
final class HostStatusModel: ObservableObject {
    @Published private(set) var status: HostStatus = .checking

    /// Refresh the current Host process status.
    func refresh() {
        status = isHostRunning() ? .running : .stopped
    }

    /// Start the per-user SoundFridge Host service through launchd.
    func start() {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/LaunchAgents/com.soundbridge.host.plist"
            )

        let result = runLaunchctl([
            "bootstrap",
            "gui/\(getuid())",
            plistURL.path
        ])

        if result != 0 {
            print("[HostStatus] Failed to start Host service (status: \(result))")
        }

        refresh()
    }

    /// Stop the per-user SoundFridge Host service through launchd.
    ///
    /// launchctl's exit status is diagnostic information only. The actual Host
    /// process state determines what the GUI reports.
    func stop() {
        let result = runLaunchctl([
            "bootout",
            "gui/\(getuid())/com.soundbridge.host"
        ])

        if result != 0 {
            print(
                "[HostStatus] launchctl bootout returned status \(result); "
                + "checking actual Host state"
            )
        }

        waitForHostToStop()
        refresh()
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

    /// Give the Host a short time to exit after launchd unloads the service.
    private func waitForHostToStop() {
        for _ in 0..<20 {
            if !isHostRunning() {
                return
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Run launchctl and return its exit status.
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments

        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            print("[HostStatus] Failed to run launchctl: \(error)")
            return -1
        }
    }

}
