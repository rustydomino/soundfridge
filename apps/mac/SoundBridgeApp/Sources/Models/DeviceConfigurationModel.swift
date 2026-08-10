import Combine
import Darwin
import Foundation

/// Darwin notification API used to tell the Host that the registry changed.
@_silgen_name("notify_post")
private func _notify_post(_ name: UnsafePointer<CChar>) -> UInt32

@_silgen_name("notify_register_dispatch")
private func _notify_register_dispatch(
    _ name: UnsafePointer<CChar>,
    _ outToken: UnsafeMutablePointer<Int32>,
    _ queue: DispatchQueue,
    _ handler: @escaping @convention(block) (Int32) -> Void
) -> UInt32

/// One device row presented by the SoundFridge configuration UI.
///
/// The stable Core Audio UID is the identity. We never use the transient
/// AudioDeviceID as persistent device identity.
struct DeviceConfigurationRow: Identifiable {
    let id: String
    let name: String
    let decision: DeviceDecision
}

/// Loads the SoundFridge device registry and exposes it to SwiftUI.
///
/// This first version is intentionally read-only. Device decision changes
/// and Host notifications will be added only after the display path works.
@MainActor
final class DeviceConfigurationModel: ObservableObject {
    @Published private(set) var devices: [DeviceConfigurationRow] = []
    @Published private(set) var loadError: String?
    @Published private(set) var saveError: String?

    private let store: DeviceRegistryStore

    private var pendingDeviceNotifyToken: Int32 = 0

    init(store: DeviceRegistryStore = DeviceRegistryStore()) {
        self.store = store
        reload()
        startPendingDeviceMonitoring()
    }

    /// Reload the registry from disk.
    func reload() {
        guard let knownDevices = store.loadDevices() else {
            devices = []
            loadError = "Unable to read the SoundFridge device configuration."
            return
        }

        loadError = nil

        devices = knownDevices.compactMap { uid, device in
            guard device.decision != .blacklisted else {
                return nil
            }

            return DeviceConfigurationRow(
                id: uid,
                name: device.name,
                decision: device.decision
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func startPendingDeviceMonitoring() {
        let status = _notify_register_dispatch(
            "com.soundbridge.pending-device",
            &pendingDeviceNotifyToken,
            DispatchQueue.main
        ) { [weak self] _ in
            Task { @MainActor in
                print("[DeviceConfiguration] New pending device; reloading registry")
                self?.reload()
            }
        }

        if status != 0 {
            print(
                "[DeviceConfiguration] Failed to register pending-device "
                    + "notification (status: \(status))"
            )
        }
    }

    /// Enable or disable SoundFridge volume control for a known device.
    ///
    /// The GUI persists the user's decision, then tells the Host to reread the
    /// registry and reconcile its managed devices immediately.
    func setVolumeControlEnabled(_ enabled: Bool, for uid: String) {
        guard var knownDevices = store.loadDevices(),
              var device = knownDevices[uid]
        else {
            saveError = "Unable to find the selected device in the SoundFridge configuration."
            return
        }

        device.decision = enabled ? .managed : .ignored
        knownDevices[uid] = device

        do {
            try store.saveDevices(knownDevices)
            saveError = nil

            let status = _notify_post(
                "com.soundbridge.device-registry-changed"
            )

            if status != 0 {
                print(
                    "[DeviceRegistry] Failed to notify Host of configuration change "
                        + "(status: \(status))"
                )
            }

            reload()
        } catch {
            print("[DeviceRegistry] Failed to save config: \(error)")
            saveError = "Unable to save the SoundFridge device configuration."
        }
    }

    /// Forget a device completely.
    ///
    /// Removing a device deletes its registry entry. If the physical device is
    /// still connected and eligible, the Host may discover it again as pending.
    func removeDevice(_ uid: String) {
        guard var knownDevices = store.loadDevices(),
              knownDevices.removeValue(forKey: uid) != nil
        else {
            saveError = "Unable to find the selected device in the SoundFridge configuration."
            return
        }

        do {
            try store.saveDevices(knownDevices)
            saveError = nil

            let status = _notify_post(
                "com.soundbridge.device-registry-changed"
            )

            if status != 0 {
                print(
                    "[DeviceRegistry] Failed to notify Host of configuration change "
                        + "(status: \(status))"
                )
            }

            reload()
        } catch {
            print("[DeviceRegistry] Failed to save config: \(error)")
            saveError = "Unable to save the SoundFridge device configuration."
        }
    }

    /// Block a device from future SoundFridge discovery and enrollment.
    ///
    /// The device remains in the registry so its stable UID can be recognized,
    /// but it is hidden from the normal device list and ignored by the Host.
    func blacklistDevice(_ uid: String) {
        guard var knownDevices = store.loadDevices(),
              var device = knownDevices[uid]
        else {
            saveError = "Unable to find the selected device in the SoundFridge configuration."
            return
        }

        device.decision = .blacklisted
        knownDevices[uid] = device

        do {
            try store.saveDevices(knownDevices)
            saveError = nil

            let status = _notify_post(
                "com.soundbridge.device-registry-changed"
            )

            if status != 0 {
                print(
                    "[DeviceRegistry] Failed to notify Host of configuration change "
                        + "(status: \(status))"
                )
            }

            reload()
        } catch {
            print("[DeviceRegistry] Failed to save config: \(error)")
            saveError = "Unable to save the SoundFridge device configuration."
        }
    }
}
