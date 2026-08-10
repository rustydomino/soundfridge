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

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SoundBridge")

        self.fileURL = appSupport.appendingPathComponent("config.plist")
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
