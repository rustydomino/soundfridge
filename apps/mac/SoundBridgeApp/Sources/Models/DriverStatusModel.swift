
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

    private let driverPath =
        "/Library/Audio/Plug-Ins/HAL/SoundBridgeDriver.driver"

    /// Check whether the SoundFridge HAL driver bundle is installed.
    func refresh() {
        status = FileManager.default.fileExists(atPath: driverPath)
            ? .installed
            : .notInstalled
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

        _ = runPrivilegedShell(command)
        refresh()
    }

    /// Remove the installed driver.
    func uninstall() {
        operationError = nil

        let quotedDriverPath = shellQuote(driverPath)

        let command =
            "if [ -e \(quotedDriverPath) ]; then " +
            "/bin/rm -rf \(quotedDriverPath) ; " +
            "fi && /usr/bin/killall coreaudiod"

        _ = runPrivilegedShell(command)
        refresh()
    }

    /// Quote a path safely for /bin/sh.
    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) + "'"
    }

    /// Execute one shell command through macOS's administrator authorization dialog.
    @discardableResult
    private func runPrivilegedShell(_ command: String) -> Bool {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source =
            "do shell script \"\(escapedCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            operationError = "Could not create the administrator operation."
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error {
            operationError = "Administrator operation failed: \(error)"
            return false
        }

        return true
    }

    func clearOperationError() {
        operationError = nil
    }

}
