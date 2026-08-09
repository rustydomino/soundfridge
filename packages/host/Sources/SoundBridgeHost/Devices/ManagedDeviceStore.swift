// Original prompt: "ok. now that we have decided plist for SF, what is next step?"
// Date: 2026-08-08
//
// Purpose:
// Persist the stable Core Audio UIDs of devices selected for Soundfridge
// management in a macOS property-list configuration file.
//
// Build/test:
//   make build
//
// Inspect the saved plist with:
//   plutil -p "$HOME/Library/Application Support/SoundBridge/config.plist"

import Foundation

/// On-disk Soundfridge configuration.
///
/// Keep the persistence format isolated here so the rest of the Host does not
/// need to know whether configuration is stored as a plist, JSON, or something
/// else.
private struct ManagedDeviceConfiguration: Codable {
    var managedDeviceUIDs: [String]
}

final class ManagedDeviceStore {
    private let fileURL: URL

    init(
        fileURL: URL = PathManager.appSupportDir
            .appendingPathComponent("config.plist")
    ) {
        self.fileURL = fileURL
    }

    /// Load the configured managed-device UIDs.
    ///
    /// Returns nil when no configuration file exists yet. This distinguishes:
    ///
    ///   nil         = Soundfridge has not been configured yet
    ///   empty Set   = configured, but no devices selected
    ///   nonempty Set = explicitly selected devices
    func loadSelectedUIDs() -> Set<String>? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let config = try PropertyListDecoder().decode(
                ManagedDeviceConfiguration.self,
                from: data
            )

            return Set(config.managedDeviceUIDs)
        } catch {
            print("[ManagedDevices] Failed to load config: \(error)")
            return nil
        }
    }

    /// Save the selected device UIDs as an XML property list.
    func saveSelectedUIDs(_ uids: Set<String>) throws {
        let config = ManagedDeviceConfiguration(
            managedDeviceUIDs: uids.sorted()
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}