//
// Original prompt: "yup let's do it."
// Date: 2026-08-08
//
// Purpose:
//   Enumerate physical macOS audio output devices and determine whether
//   Core Audio exposes writable volume control for each device.
//
// How to run:
//   From the soundfridge repository root:
//
//       swift tools/volume_probe.swift
//
//   This tool is read-only. It does not change device volume or audio routing.
//

import Foundation
import CoreAudio
import Darwin

// MARK: - Helpers

/// Return a CFString-backed Core Audio property as a Swift String.
func getStringProperty(
    deviceID: AudioDeviceID,
    selector: AudioObjectPropertySelector
) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            pointer
        )
    }

    guard status == noErr,
          let cfValue = value?.takeUnretainedValue() else {
        return nil
    }

    return cfValue as String
}

/// Return the Core Audio transport type for a device.
func getTransportType(deviceID: AudioDeviceID) -> UInt32? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &size,
        &value
    )

    return status == noErr ? value : nil
}

/// Convert a Core Audio transport constant into a readable name.
func transportName(_ type: UInt32) -> String {
    switch type {
    case kAudioDeviceTransportTypeBuiltIn:
        return "Built-in"
    case kAudioDeviceTransportTypeBluetooth:
        return "Bluetooth"
    case kAudioDeviceTransportTypeUSB:
        return "USB"
    case kAudioDeviceTransportTypeDisplayPort:
        return "DisplayPort"
    case kAudioDeviceTransportTypeHDMI:
        return "HDMI"
    case kAudioDeviceTransportTypeThunderbolt:
        return "Thunderbolt"
    case kAudioDeviceTransportTypeAirPlay:
        return "AirPlay"
    case kAudioDeviceTransportTypeVirtual:
        return "Virtual"
    case kAudioDeviceTransportTypeAggregate:
        return "Aggregate"
    case kAudioDeviceTransportTypePCI:
        return "PCI"
    case kAudioDeviceTransportTypeFireWire:
        return "FireWire"
    default:
        return "Other (0x\(String(type, radix: 16)))"
    }
}

/// Determine whether this AudioDevice actually has output streams.
func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    var size: UInt32 = 0

    let status = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &size
    )

    return status == noErr && size > 0
}

// Original prompt: "got it. ok let's do it"
// Date: 2026-08-08
// Usage: Add this function to tools/volume_probe.swift, then run:
//   swift tools/volume_probe.swift
//
// Determine the total number of output channels exposed by a Core Audio device.
// Core Audio returns an AudioBufferList describing the device's output streams.
// Each buffer reports how many channels it contains; we add them together.
func getOutputChannelCount(deviceID: AudioDeviceID) -> Int? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // First ask Core Audio how much memory is required for the AudioBufferList.
    var size: UInt32 = 0

    let sizeStatus = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &size
    )

    guard sizeStatus == noErr, size > 0 else {
        return nil
    }

    // AudioBufferList is variable-sized, so allocate exactly the amount
    // of memory Core Audio told us it needs.
    let rawPointer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )

    defer {
        rawPointer.deallocate()
    }

    let bufferListPointer = rawPointer.bindMemory(
        to: AudioBufferList.self,
        capacity: 1
    )

    let dataStatus = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &size,
        bufferListPointer
    )

    guard dataStatus == noErr else {
        return nil
    }

    // This Swift helper lets us iterate through every AudioBuffer in the
    // variable-length AudioBufferList safely.
    let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)

    return buffers.reduce(0) {
        $0 + Int($1.mNumberChannels)
    }
}

// MARK: - Volume capability probing

struct VolumeProbeResult {
    let element: UInt32
    let exists: Bool
    let settable: Bool
    let currentValue: Float32?
    let settableStatus: OSStatus?
}

/// Probe kAudioDevicePropertyVolumeScalar for one device element.
///
/// We do NOT write anything. AudioObjectIsPropertySettable merely asks
/// Core Audio whether AudioObjectSetPropertyData would be permitted.
func probeVolume(
    deviceID: AudioDeviceID,
    element: UInt32
) -> VolumeProbeResult {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
    )

    let exists = AudioObjectHasProperty(deviceID, &address)

    guard exists else {
        return VolumeProbeResult(
            element: element,
            exists: false,
            settable: false,
            currentValue: nil,
            settableStatus: nil
        )
    }

    // Ask Core Audio whether this property can actually be changed.
    var isSettable = DarwinBoolean(false)

    let settableStatus = AudioObjectIsPropertySettable(
        deviceID,
        &address,
        &isSettable
    )

    // Reading the current scalar value is useful diagnostic information,
    // but failure to read it does not affect whether the property exists.
    var volume: Float32 = 0
    var volumeSize = UInt32(MemoryLayout<Float32>.size)

    let readStatus = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &volumeSize,
        &volume
    )

    return VolumeProbeResult(
        element: element,
        exists: true,
        settable: settableStatus == noErr && isSettable.boolValue,
        currentValue: readStatus == noErr ? volume : nil,
        settableStatus: settableStatus
    )
}

/// Human-readable name for the elements SoundBridge currently checks.
func elementName(_ element: UInt32) -> String {
    switch element {
    case kAudioObjectPropertyElementMain:
        return "master"
    case 1:
        return "channel 1"
    case 2:
        return "channel 2"
    default:
        return "element \(element)"
    }
}

// MARK: - Device enumeration

var deviceListAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

var deviceListSize: UInt32 = 0

guard AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject),
    &deviceListAddress,
    0,
    nil,
    &deviceListSize
) == noErr else {
    fatalError("Unable to obtain Core Audio device-list size.")
}

let deviceCount =
    Int(deviceListSize) / MemoryLayout<AudioDeviceID>.size

var deviceIDs = [AudioDeviceID](
    repeating: 0,
    count: deviceCount
)

guard AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &deviceListAddress,
    0,
    nil,
    &deviceListSize,
    &deviceIDs
) == noErr else {
    fatalError("Unable to obtain Core Audio device list.")
}

print("Soundfridge volume capability probe")
print("===================================")

for deviceID in deviceIDs {
    guard hasOutputStreams(deviceID: deviceID) else {
        continue
    }

    guard let transport = getTransportType(deviceID: deviceID) else {
        continue
    }

    // We care about physical devices. Soundfridge proxies, aggregate devices,
    // Teams audio, and other virtual outputs should not influence this test.
    if transport == kAudioDeviceTransportTypeVirtual ||
       transport == kAudioDeviceTransportTypeAggregate {
        continue
    }

    let name =
        getStringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceNameCFString
        ) ?? "<unknown>"

    let uid =
        getStringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID
        ) ?? "<unknown>"

    let manufacturer =
        getStringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceManufacturerCFString
        ) ?? "<unknown>"

    // Original prompt: "got it. ok let's do it"
    // Date: 2026-08-08
    // Usage: This replaces the previous hard-coded main/1/2 element list.
    //
    // Ask the device how many output channels it actually exposes rather
    // than assuming that every device is stereo.
    let outputChannelCount = getOutputChannelCount(deviceID: deviceID) ?? 0

    var elements: [UInt32] = [
        kAudioObjectPropertyElementMain
    ]

    // Core Audio channel elements are numbered starting at 1.
    // Element 0 ("main") was already added above.
    if outputChannelCount > 0 {
        elements.append(
            contentsOf: (1...outputChannelCount).map { UInt32($0) }
        )
    }


    let results = elements.map {
        probeVolume(deviceID: deviceID, element: $0)
    }

    // This is the proposed Soundfridge criterion:
    // if ANY relevant output volume property is writable through Core Audio,
    // the physical device already has software volume control and does not
    // need a proxy.
    let hasWritableVolume =
        results.contains { $0.exists && $0.settable }

    print("")
    print(name)
    print(String(repeating: "-", count: name.count))
    print("  AudioDeviceID: \(deviceID)")
    print("  UID:           \(uid)")
    print("  Manufacturer:  \(manufacturer)")
    print("  Transport:     \(transportName(transport))")
    // Original prompt: "got it. ok let's do it"
    // Date: 2026-08-08
    // Usage: Diagnostic output showing the channel count reported by Core Audio.
    print("  Output channels: \(outputChannelCount)")

    for result in results {
        let label = elementName(result.element)

        if !result.exists {
            print("  \(label): volume property absent")
            continue
        }

        let writableText =
            result.settable ? "SETTABLE" : "not settable"

        if let value = result.currentValue {
            print(
                "  \(label): volume property present, "
                + "\(writableText), current=\(String(format: "%.3f", value))"
            )
        } else {
            print(
                "  \(label): volume property present, "
                + "\(writableText), current=<unreadable>"
            )
        }

        if let status = result.settableStatus,
           status != noErr {
            print("    AudioObjectIsPropertySettable status: \(status)")
        }
    }

    print("")

    if hasWritableVolume {
        print("  RESULT: macOS CAN control volume")
        print("          -> Soundfridge proxy NOT needed")
    } else {
        print("  RESULT: no writable Core Audio volume control")
        print("          -> Soundfridge proxy NEEDED")
    }
}

print("")
