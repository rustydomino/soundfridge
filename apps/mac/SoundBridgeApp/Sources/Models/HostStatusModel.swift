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
    case probablyUp
    case notDetected
    case stopped
}

/// Checks whether the independent SoundFridge Host process is running.
///
/// This does not start or stop the Host. It only observes its current state.
@MainActor
final class HostStatusModel: ObservableObject {
    @Published private(set) var status: HostStatus = .checking
    @Published private(set) var lastChecked: Date?

    private let serviceLabel = "com.soundbridge.host"

    private var serviceDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/SoundBridge",
                isDirectory: true
            )
    }

    private var installedHostURL: URL {
        serviceDirectoryURL.appendingPathComponent("SoundBridgeHost")
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/LaunchAgents/\(serviceLabel).plist"
            )
    }

    private var bundledHostURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("SoundBridgeHost")
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

    /// Install/update the bundled Host and start it through launchd.
    func start() {
        guard prepareUserService() else {
            refresh()
            return
        }

        let result = runLaunchctl([
            "bootstrap",
            "gui/\(getuid())",
            launchAgentURL.path
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

    /// Install the Host into a stable per-user location and generate its
    /// LaunchAgent configuration.
    ///
    /// No administrator privileges are needed because both destinations live
    /// inside the current user's home directory.
    private func prepareUserService() -> Bool {
        let fileManager = FileManager.default

        guard let bundledHostURL,
            fileManager.isExecutableFile(atPath: bundledHostURL.path) else {
            print("[HostStatus] Bundled SoundBridgeHost is missing or not executable")
            return false
        }

        do {
            // Install/update the Host binary.
            try fileManager.createDirectory(
                at: serviceDirectoryURL,
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: installedHostURL.path) {
                try fileManager.removeItem(at: installedHostURL)
            }

            try fileManager.copyItem(
                at: bundledHostURL,
                to: installedHostURL
            )

            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: installedHostURL.path
            )

            // Create/update ~/Library/LaunchAgents/com.soundbridge.host.plist.
            try fileManager.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": serviceLabel,
                "ProgramArguments": [installedHostURL.path],
                "RunAtLoad": true,
                "KeepAlive": true,
                "ProcessType": "Interactive"
            ]

            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )

            try plistData.write(
                to: launchAgentURL,
                options: .atomic
            )

            return true

        } catch {
            print("[HostStatus] Failed to prepare Host service: \(error)")
            return false
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

    /// Check whether launchd currently has the Host service loaded.
    ///
    /// This is a snapshot only; SoundFridge does not continuously monitor it.
    private func isServiceLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "print",
            "gui/\(getuid())/\(serviceLabel)"
        ]

        // A missing service is normal when SoundFridge is intentionally stopped,
        // so suppress launchctl's diagnostic output here.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
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
