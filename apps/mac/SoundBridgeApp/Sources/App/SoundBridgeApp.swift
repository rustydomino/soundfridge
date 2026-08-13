import SwiftUI
import Foundation
import Darwin
import AppKit
import CoreText
import CoreGraphics
import CoreAudio

// Main entry point - AppKit-based app with SwiftUI views
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set to true during uninstall to suppress Host terminationHandler from
    /// calling NSApp.terminate prematurely.
    var isUninstalling = false
    var deviceConfigurationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SoundFridge's GUI is a configuration utility.
        // The background Host has its own lifecycle and continues independently.
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()

        Task { @MainActor in
            showDeviceConfigurationWindow()
        }
    }

    /// Build the small standard menu set needed by the SoundFridge GUI.
    ///
    /// SoundFridge is a single-window configuration utility rather than a
    /// document-based app, so it does not need File/Edit/View menus.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // SoundFridge menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "SoundFridge")

        let aboutItem = NSMenuItem(
            title: "About SoundFridge",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit SoundFridge",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        // Leave the target nil so AppKit sends the command through the responder
        // chain to whichever window is currently active.
        closeItem.target = nil
        windowMenu.addItem(closeItem)

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")

        let helpItem = NSMenuItem(
            title: "SoundFridge Help",
            action: #selector(NSApplication.showHelp(_:)),
            keyEquivalent: "?"
        )
        helpItem.target = NSApp
        helpMenu.addItem(helpItem)

        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        // Tell AppKit which menu is the application's Help menu.
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = mainMenu
    }

    @MainActor
    func showDeviceConfigurationWindow() {
        // Reuse the existing window if it has already been created.
        if let window = deviceConfigurationWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = DeviceConfigurationModel()
        let hostStatusModel = HostStatusModel()
        let driverStatusModel = DriverStatusModel()

        let view = DeviceConfigurationView(
            model: model,
            hostStatusModel: hostStatusModel,
            driverStatusModel: driverStatusModel
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "SoundFridge"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false

        deviceConfigurationWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The SoundFridge GUI does not own the background Host.
        // Closing the configuration app must not interrupt audio service.
        print("SoundFridge configuration app terminating")
    }

    /// SoundFridge's GUI is only a configuration utility.
    ///
    /// Closing its last window quits the GUI process. The background Host has
    /// its own lifecycle and continues running independently.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    /// Poll a Process for exit up to timeout seconds.
    private func waitForProcessExit(_ process: Process, timeout: TimeInterval, logger: (String) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            logger("Process \(process.processIdentifier) did not exit within \(timeout)s")
        }
    }

    /// Poll a PID for exit up to timeout seconds.
    private func waitForPIDExit(_ pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                return true // no longer running
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return kill(pid, 0) != 0
    }

    /// Clean up temporary files that keep proxies alive.
    private func cleanupTempIPC(logger: (String) -> Void) {
        let fm = FileManager.default
        let controlFile = "/tmp/soundbridge-devices.txt"
        if fm.fileExists(atPath: controlFile) {
            logger("Removing control file \(controlFile)")
            unlink(controlFile)
        }

        // Remove shared memory files the driver might watch
        if let tmpItems = try? fm.contentsOfDirectory(atPath: "/tmp") {
            for item in tmpItems where item.hasPrefix("soundbridge-") {
                let path = "/tmp/\(item)"
                logger("Removing shared memory file \(path)")
                unlink(path)
            }
        }
    }

    func performCleanup(logger: (String) -> Void = { print($0) }) {
        logger("[Cleanup] Starting cleanup process...")

        // 1. Restore default device to physical device (if currently on proxy)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var currentDeviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        if AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &currentDeviceID
        ) == noErr {
            // Get current device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceName: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

            let nameStatus = withUnsafeMutablePointer(to: &deviceName) { ptr in
                AudioObjectGetPropertyData(currentDeviceID, &nameAddress, 0, nil, &nameSize, ptr)
            }
            if nameStatus == noErr, let name = deviceName?.takeUnretainedValue() as String? {

                // If currently on a SoundBridge proxy, switch back to physical device
                if name.contains("SoundBridge") {
                    logger("[Cleanup] Currently on proxy device: \(name)")

                    // Get proxy UID
                    var uidAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyDeviceUID,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )

                    var deviceUID: Unmanaged<CFString>?
                    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

                    let uidStatus = withUnsafeMutablePointer(to: &deviceUID) { ptr in
                        AudioObjectGetPropertyData(currentDeviceID, &uidAddress, 0, nil, &uidSize, ptr)
                    }
                    if uidStatus == noErr, let proxyUIDStr = deviceUID?.takeUnretainedValue() as String? {

                        // Extract physical device UID (remove "-soundbridge" suffix)
                        if let physicalUID = proxyUIDStr.components(separatedBy: "-soundbridge").first {
                            logger("[Cleanup] Looking for physical device with UID: \(physicalUID)")

                            // Find the physical device
                            if let physicalDeviceID = findDeviceByUID(physicalUID) {
                                logger("[Cleanup] Restoring default device to physical device (ID: \(physicalDeviceID))")

                                var newDeviceID = physicalDeviceID
                                let result = AudioObjectSetPropertyData(
                                    AudioObjectID(kAudioObjectSystemObject),
                                    &propertyAddress,
                                    0,
                                    nil,
                                    UInt32(MemoryLayout<AudioDeviceID>.size),
                                    &newDeviceID
                                )

                                // Also restore system output device
                                var systemAddress = AudioObjectPropertyAddress(
                                    mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                    mScope: kAudioObjectPropertyScopeGlobal,
                                    mElement: kAudioObjectPropertyElementMain
                                )
                                var systemDeviceID = physicalDeviceID
                                AudioObjectSetPropertyData(
                                    AudioObjectID(kAudioObjectSystemObject),
                                    &systemAddress,
                                    0,
                                    nil,
                                    UInt32(MemoryLayout<AudioDeviceID>.size),
                                    &systemDeviceID
                                )

                                if result == noErr {
                                    logger("[Cleanup] Restored to physical device")
                                    // CoreAudio device switch is synchronous, no sleep needed
                                } else {
                                    logger("[Cleanup] WARNING: Failed to restore device (error \(result))")
                                }
                            } else {
                                logger("[Cleanup] WARNING: Could not find physical device with UID: \(physicalUID)")
                            }
                        }
                    }
                } else {
                    logger("[Cleanup] Already on physical device: \(name)")
                }
            }
        }

        // 2. Remove control file - driver will detect and remove proxies
        let controlFilePath = "/tmp/soundbridge-devices.txt"
        logger("[Cleanup] Removing control file: \(controlFilePath)")
        unlink(controlFilePath)

        // 3. Wait for driver to remove devices (driver polls every 100ms)
        logger("[Cleanup] Waiting for driver to remove proxy devices...")
        Thread.sleep(forTimeInterval: 0.5)

        logger("[Cleanup] Cleanup complete")
    }

    func findDeviceByUID(_ targetUID: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        // Find device with matching UID
        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

            let uidStatus = withUnsafeMutablePointer(to: &deviceUID) { ptr in
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
            }
            if uidStatus == noErr, let uid = deviceUID?.takeUnretainedValue() as String? {
                if uid == targetUID {
                    return deviceID
                }
            }
        }

        return nil
    }

    func checkAndLoadDriverIfNeeded() {
        // Check if SoundBridge driver is already loaded
        if isDriverLoaded() {
            print("SoundBridge driver already loaded, no need to restart coreaudiod")
            return
        }

        print("WARNING: SoundBridge driver not detected, attempting to load...")

        // Check if driver is installed
        let driverPath = "/Library/Audio/Plug-Ins/HAL/SoundBridgeDriver.driver"
        guard FileManager.default.fileExists(atPath: driverPath) else {
            showAlert(
                "Driver Not Installed",
                "SoundBridge driver is not installed at \(driverPath)\n\nInstall it with:\ncd packages/driver && ./install.sh && sudo killall coreaudiod"
            )
            return
        }

        // Attempt to restart coreaudiod
        // This uses AppleScript to request admin privileges
        let script = """
        do shell script "killall coreaudiod" with administrator privileges
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("Failed to restart coreaudiod: \(error)")
            showAlert("Driver Load Failed", "Could not restart coreaudiod. You may need to manually run:\nsudo killall coreaudiod")
        } else {
            print("coreaudiod restarted successfully")
            // Wait a bit for coreaudiod to restart
            Thread.sleep(forTimeInterval: 2.0)
        }
    }

    func isDriverLoaded() -> Bool {
        // Use system_profiler to check if SoundBridge devices are visible
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPAudioDataType"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("SoundBridge")
            }
        } catch {
            print("Failed to check driver status: \(error)")
        }

        return false
    }

    func getArchitecture() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let arch = String(cString: machine)
        
        // Map to SwiftPM architecture names
        if arch.contains("arm64") {
            return "arm64-apple-macosx"
        } else if arch.contains("x86_64") {
            return "x86_64-apple-macosx"
        }
        return nil
    }
    
    func loadLogoImage() -> NSImage? {
        let fileManager = FileManager.default
        var logoURL: URL?

        // PRIORITY 1: Try using Bundle's resource API (works across bundle structures)
        // First try to find the resource bundle
        if let resourceBundleURL = Bundle.main.url(forResource: "SoundBridgeApp_SoundBridgeApp", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let logoPath = resourceBundle.url(forResource: "icons/soundbridge-menu", withExtension: "svg") {
            print("Found menu icon via resource bundle API: \(logoPath.path)")
            logoURL = logoPath
        }

        // PRIORITY 2: Try SwiftPM resource bundle (production builds)
        // SwiftPM creates a separate bundle named "<Target>_<Target>.bundle"
        if logoURL == nil, let executableURL = Bundle.main.executableURL {
            let bundleName = "SoundBridgeApp_SoundBridgeApp.bundle"
            let resourceBundleURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
                .appendingPathComponent("Resources/icons/soundbridge-menu.svg")

            if fileManager.fileExists(atPath: resourceBundleURL.path) {
                print("Found logo in SwiftPM bundle: \(resourceBundleURL.path)")
                logoURL = resourceBundleURL
            }
        }

        // PRIORITY 3: Try main bundle's built-in resource lookup
        if logoURL == nil, let mainBundleURL = Bundle.main.url(forResource: "icons/soundbridge-menu", withExtension: "svg") {
            print("Found menu icon via main bundle: \(mainBundleURL.path)")
            logoURL = mainBundleURL
        }

        // PRIORITY 4: Try main bundle resources (alternative bundle structure)
        if logoURL == nil, let resourcePath = Bundle.main.resourcePath {
            let possiblePaths = [
                "\(resourcePath)/Resources/icons/soundbridge-menu.svg",
                "\(resourcePath)/icons/soundbridge-menu.svg"
            ]

            for path in possiblePaths {
                if fileManager.fileExists(atPath: path) {
                    print("Found logo in main bundle: \(path)")
                    logoURL = URL(fileURLWithPath: path)
                    break
                }
            }
        }

        // PRIORITY 5: Development - relative to executable
        if logoURL == nil, let executablePath = Bundle.main.executablePath {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            let sourcePath = (executableDir as NSString).appendingPathComponent("../../../Sources/Resources/icons/soundbridge-menu.svg")
            let normalizedPath = (sourcePath as NSString).standardizingPath
            if fileManager.fileExists(atPath: normalizedPath) {
                print("Found logo in development Sources: \(normalizedPath)")
                logoURL = URL(fileURLWithPath: normalizedPath)
            }
        }

        // PRIORITY 6: Development - absolute path from repo root
        if logoURL == nil {
            let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let absolutePath = "\(homeDir)/soundbridge/apps/mac/SoundBridgeApp/Sources/Resources/icons/soundbridge-menu.svg"
            if fileManager.fileExists(atPath: absolutePath) {
                print("Found menu icon at absolute path: \(absolutePath)")
                logoURL = URL(fileURLWithPath: absolutePath)
            }
        }

        guard let url = logoURL else {
            print("Failed to find soundbridge-menu.svg in any location")
            return nil
        }

        // Load SVG (NSImage supports SVG on macOS 10.15+)
        guard let image = NSImage(contentsOf: url) else {
            print("Failed to load image from: \(url.path)")
            return nil
        }

        // Resize to appropriate menu bar size (typically 18-22px)
        let size = NSSize(width: 16, height: 16)
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        resizedImage.unlockFocus()

        print("Successfully loaded and resized logo")
        return resizedImage
    }
    
    func registerCustomFont() {
        let fileManager = FileManager.default
        var fontURL: URL?

        // PRIORITY 1: Try using Bundle's resource API (works across bundle structures)
        if let resourceBundleURL = Bundle.main.url(forResource: "SoundBridgeApp_SoundBridgeApp", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let fontPath = resourceBundle.url(forResource: "fonts/SignPainterHouseScript", withExtension: "ttf") {
            print("Found font via resource bundle API: \(fontPath.path)")
            fontURL = fontPath
        }

        // PRIORITY 2: Try SwiftPM resource bundle (production builds)
        if fontURL == nil, let executableURL = Bundle.main.executableURL {
            let bundleName = "SoundBridgeApp_SoundBridgeApp.bundle"
            let resourceBundleURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
                .appendingPathComponent("Resources/fonts/SignPainterHouseScript.ttf")

            if fileManager.fileExists(atPath: resourceBundleURL.path) {
                print("Found font in SwiftPM bundle: \(resourceBundleURL.path)")
                fontURL = resourceBundleURL
            }
        }

        // PRIORITY 3: Try main bundle's built-in resource lookup
        if fontURL == nil, let mainBundleURL = Bundle.main.url(forResource: "fonts/SignPainterHouseScript", withExtension: "ttf") {
            print("Found font via main bundle: \(mainBundleURL.path)")
            fontURL = mainBundleURL
        }

        // PRIORITY 4: Try main bundle resources (alternative bundle structure)
        if fontURL == nil, let resourcePath = Bundle.main.resourcePath {
            let possiblePaths = [
                "\(resourcePath)/Resources/fonts/SignPainterHouseScript.ttf",
                "\(resourcePath)/fonts/SignPainterHouseScript.ttf"
            ]

            for path in possiblePaths {
                if fileManager.fileExists(atPath: path) {
                    print("Found font in main bundle: \(path)")
                    fontURL = URL(fileURLWithPath: path)
                    break
                }
            }
        }

        // PRIORITY 5: Development - relative to executable
        if fontURL == nil, let executablePath = Bundle.main.executablePath {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            let sourcePath = (executableDir as NSString).appendingPathComponent("../../../Sources/Resources/fonts/SignPainterHouseScript.ttf")
            let normalizedPath = (sourcePath as NSString).standardizingPath
            if fileManager.fileExists(atPath: normalizedPath) {
                print("Found font in development Sources: \(normalizedPath)")
                fontURL = URL(fileURLWithPath: normalizedPath)
            }
        }

        // PRIORITY 6: Development - absolute path from repo root
        if fontURL == nil {
            let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let absolutePath = "\(homeDir)/soundbridge/apps/mac/SoundBridgeApp/Sources/Resources/fonts/SignPainterHouseScript.ttf"
            if fileManager.fileExists(atPath: absolutePath) {
                print("Found font at absolute path: \(absolutePath)")
                fontURL = URL(fileURLWithPath: absolutePath)
            }
        }

        guard let url = fontURL else {
            print("Failed to find SignPainterHouseScript.ttf in any location")
            return
        }

        var error: Unmanaged<CFError>?
        let result = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        if result {
            print("Successfully registered custom font")
        } else if let error = error {
            print("Failed to register font: \(error.takeRetainedValue())")
        }
    }
    
    func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

}

// Main entry point - check for command-line flags before launching app
extension AppDelegate {
    static func main() {
        // Launch the app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
