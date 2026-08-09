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

enum DeviceDecision: String, Codable {
    case pending
    case managed
    case ignored
}

struct KnownDevice: Codable {
    var name: String
    var decision: DeviceDecision
}

private struct DeviceRegistryConfiguration: Codable {
    var knownDevices: [String: KnownDevice]
}

final class DeviceRegistryStore {
    private let fileURL: URL

    init(
        fileURL: URL = PathManager.appSupportDir
            .appendingPathComponent("config.plist")
    ) {
        self.fileURL = fileURL
    }

    func loadDevices() -> [String: KnownDevice]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)

            let config = try PropertyListDecoder().decode(
                DeviceRegistryConfiguration.self,
                from: data
            )

            return config.knownDevices
        } catch {
            print("[DeviceRegistry] Failed to load config: \(error)")
            return nil
        }
    }

    func saveDevices(_ devices: [String: KnownDevice]) throws {
        let config = DeviceRegistryConfiguration(
            knownDevices: devices
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
