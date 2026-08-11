
import Combine
import Foundation

enum DriverStatus {
    case checking
    case installed
    case notInstalled
}

@MainActor
final class DriverStatusModel: ObservableObject {
    @Published private(set) var status: DriverStatus = .checking
    @Published private(set) var operationError: String?

private enum PrivilegedOperationResult: Sendable {
    case success
    case cancelled
    case failure(String)
}

    private let driverPath =
        "/Library/Audio/Plug-Ins/HAL/SoundBridgeDriver.driver"

    /// Check whether the SoundFridge HAL driver bundle is installed.
    func refresh() {
        status = FileManager.default.fileExists(atPath: driverPath)
            ? .installed
            : .notInstalled
    }

    func clearOperationError() {
        operationError = nil
    }
    
    /// Install the driver bundled inside SoundFridge.app.
    func install() {
        operationError = nil

        guard let resourcesURL = Bundle.main.resourceURL else {
            operationError = "Could not locate SoundFridge's Resources directory."
            return
        }

        let bundledDriverURL =
            resourcesURL.appendingPathComponent("SoundBridgeDriver.driver")

        guard FileManager.default.fileExists(atPath: bundledDriverURL.path) else {
            operationError =
                "SoundBridgeDriver.driver is missing from the SoundFridge app bundle."
            return
        }

        let installDirectory =
            (driverPath as NSString).deletingLastPathComponent

        let command = [
            "/bin/mkdir -p \(shellQuote(installDirectory))",
            "/usr/bin/ditto \(shellQuote(bundledDriverURL.path)) \(shellQuote(driverPath))",
            "/usr/sbin/chown -R root:wheel \(shellQuote(driverPath))",
            "/usr/bin/killall coreaudiod",
        ].joined(separator: " && ")

        Task { [weak self] in
            guard let self else { return }

            let result = await Task.detached(priority: .utility) {
                Self.runPrivilegedShell(command)
            }.value

            self.handlePrivilegedResult(result)
            self.refresh()
        }
    }

    /// Remove the installed driver.
    func uninstall() {
        operationError = nil

        let quotedDriverPath = shellQuote(driverPath)

        let command =
            "if [ -e \(quotedDriverPath) ]; then " +
            "/bin/rm -rf \(quotedDriverPath) ; " +
            "fi && /usr/bin/killall coreaudiod"

        Task { [weak self] in
            guard let self else { return }

            let result = await Task.detached(priority: .utility) {
                Self.runPrivilegedShell(command)
            }.value

            self.handlePrivilegedResult(result)
            self.refresh()
        }
    }

    /// Quote a path safely for /bin/sh.
    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) + "'"
    }

    /// Execute the administrator operation away from the main/UI thread.
    ///
    /// A fresh NSAppleScript instance is created and used entirely on this
    /// background task; it is never shared between threads.
    nonisolated private static func runPrivilegedShell(
        _ command: String
    ) -> PrivilegedOperationResult {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source =
            "do shell script \"\(escapedCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            return .failure(
                "Could not create the administrator operation."
            )
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        // AppleScript error -128 means the user intentionally cancelled.
        if let error,
        let errorNumber = error["NSAppleScriptErrorNumber"] as? NSNumber,
        errorNumber.intValue == -128 {
            return .cancelled
        }

        if let error {
            return .failure(
                "Administrator operation failed: \(error)"
            )
        }

        return .success
    }   

    /// Apply the result back on DriverStatusModel's main-actor context.
    private func handlePrivilegedResult(
        _ result: PrivilegedOperationResult
    ) {
        switch result {
        case .success, .cancelled:
            break

        case .failure(let message):
            operationError = message
        }
    }
}
