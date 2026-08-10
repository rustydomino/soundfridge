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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "SoundBridgeHost"]

        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            status = task.terminationStatus == 0 ? .running : .stopped
        } catch {
            print("[HostStatus] Failed to check Host process: \(error)")
            status = .stopped
        }
    }
}