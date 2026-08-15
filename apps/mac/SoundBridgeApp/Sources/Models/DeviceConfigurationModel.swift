import Combine
import Darwin
import Foundation
import CoreAudio

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

@_silgen_name("notify_cancel")
nonisolated private func _notify_cancel(_ token: Int32) -> UInt32

/// One device row presented by the SoundFridge configuration UI.
///
/// The stable Core Audio UID is the identity. We never use the transient
/// AudioDeviceID as persistent device identity.
struct DeviceConfigurationRow: Identifiable {
    let id: String
    let name: String
    let decision: DeviceDecision
    let isConnected: Bool
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
    @Published private(set) var blacklistedDevices: [DeviceConfigurationRow] = []

    /// Devices discovered by the Host that are waiting for the user to decide
    /// whether SoundFridge should manage them.
    var pendingDevices: [DeviceConfigurationRow] {
        devices.filter {
            $0.decision == .pending
        }
    }
    
    /// Devices that Core Audio reports as currently connected.
    var connectedDevices: [DeviceConfigurationRow] {
        devices.filter {
            $0.isConnected
        }
    }

    /// Pending devices that are still physically connected and can be managed now.
    var connectedPendingDevices: [DeviceConfigurationRow] {
        pendingDevices.filter {
            $0.isConnected
        }
    }

    /// Remembered devices that are not currently present in Core Audio.
    var disconnectedDevices: [DeviceConfigurationRow] {
        devices.filter {
            !$0.isConnected
        }
    }
    
    private let store: DeviceRegistryStore

    private var pendingDeviceNotifyToken: Int32 = 0
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    init(store: DeviceRegistryStore? = nil) {
        self.store = store ?? DeviceRegistryStore()
        reload()
        startPendingDeviceMonitoring()
        startDeviceConnectionMonitoring()
    }

    /// Reload the registry from disk.
    func reload() {
        guard let knownDevices = store.loadDevices() else {
            devices = []
            blacklistedDevices = []
            loadError = "Unable to read the SoundFridge device configuration."
            return
        }

        loadError = nil
        let connectedUIDs = connectedDeviceUIDs()

        let rows = knownDevices.map { uid, device in
            DeviceConfigurationRow(
                id: uid,
                name: device.name,
                decision: device.decision,
                isConnected: connectedUIDs.contains(uid)
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        devices = rows.filter {
            $0.decision != .blacklisted
        }

        blacklistedDevices = rows.filter {
            $0.decision == .blacklisted
        }
    }

    /// Return the stable UIDs of audio devices currently present in Core Audio.
    ///
    /// The registry remembers devices across disconnects, while Core Audio's
    /// current device list tells us which of those remembered devices are
    /// actually connected right now.
    private func connectedDeviceUIDs() -> Set<String> {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size

        guard deviceCount > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: deviceCount
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        var connectedUIDs = Set<String>()

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: Unmanaged<CFString>?
            var uidSize = UInt32(
                MemoryLayout<Unmanaged<CFString>?>.size
            )

            let status = withUnsafeMutablePointer(to: &deviceUID) { pointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &uidAddress,
                    0,
                    nil,
                    &uidSize,
                    pointer
                )
            }

            if status == noErr,
               let uid = deviceUID?.takeUnretainedValue() as String? {
                connectedUIDs.insert(uid)
            }
        }

        return connectedUIDs
    }
    
    /// Return true when a currently connected device also exposes input streams.
    ///
    /// SoundFridge only manages output audio, but macOS may display a microphone
    /// privacy prompt when Core Audio starts I/O on a duplex device.
    func deviceHasInput(for uid: String) -> Bool {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return false
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size

        guard deviceCount > 0 else {
            return false
        }

        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: deviceCount
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return false
        }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: Unmanaged<CFString>?
            var uidSize = UInt32(
                MemoryLayout<Unmanaged<CFString>?>.size
            )

            let uidStatus = withUnsafeMutablePointer(to: &deviceUID) { pointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &uidAddress,
                    0,
                    nil,
                    &uidSize,
                    pointer
                )
            }

            guard uidStatus == noErr,
                  let currentUID = deviceUID?.takeUnretainedValue() as String?,
                  currentUID == uid
            else {
                continue
            }

            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0

            return AudioObjectGetPropertyDataSize(
                deviceID,
                &inputAddress,
                0,
                nil,
                &inputSize
            ) == noErr && inputSize > 0
        }

        return false
    }
    
    private func startDeviceConnectionMonitoring() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                print(
                    "[DeviceConfiguration] Core Audio device list changed; reloading"
                )
                self?.reload()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            listener
        )

        if status == noErr {
            deviceListListener = listener
        } else {
            print(
                "[DeviceConfiguration] Failed to register Core Audio device "
                    + "listener (OSStatus: \(status))"
            )
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

    /// Return a blacklisted device to the normal device list.
    ///
    /// The device becomes pending again so the user can decide whether
    /// SoundFridge should manage it.
    func removeFromBlacklist(_ uid: String) {
        guard var knownDevices = store.loadDevices(),
            var device = knownDevices[uid] else {
            saveError = "Unable to find the selected device in the SoundFridge configuration."
            return
        }

        device.decision = .pending
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

    /// Remove every device from the blacklist.
    func clearBlacklist() {
        guard var knownDevices = store.loadDevices() else {
            saveError = "Unable to read the SoundFridge device configuration."
            return
        }

        var changed = false

        for uid in knownDevices.keys {
            guard var device = knownDevices[uid],
                device.decision == .blacklisted else {
                continue
            }

            device.decision = .pending
            knownDevices[uid] = device
            changed = true
        }

        guard changed else {
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

    deinit {
        if let deviceListListener {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                DispatchQueue.main,
                deviceListListener
            )
        }

        if pendingDeviceNotifyToken != 0 {
            _ = _notify_cancel(pendingDeviceNotifyToken)
        }
    }
}
