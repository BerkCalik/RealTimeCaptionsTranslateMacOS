import CoreAudio
import Foundation

enum CoreAudioDeviceManager {
    static func inputDevices() throws -> [AudioInputDevice] {
        let devices = try allAudioDeviceIDs()
        var mapped: [AudioInputDevice] = []

        for deviceID in devices {
            guard let descriptor = try? descriptor(for: deviceID) else {
                continue
            }

            let isBlackHole = descriptor.name.localizedCaseInsensitiveContains("blackhole")
            if descriptor.inputChannels > 0 || isBlackHole {
                mapped.append(AudioInputDevice(id: String(deviceID), name: descriptor.name))
            }
        }

        return mapped.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        try check(status: status, operation: "Read default input device")

        return deviceID
    }

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        )
        try check(status: status, operation: "Set default input device")
    }

    private static func allAudioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementWildcard
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        try check(status: status, operation: "Read audio device data size")

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        try check(status: status, operation: "Read audio device list")

        return deviceIDs
    }

    private static func descriptor(for deviceID: AudioDeviceID) throws -> DeviceDescriptor {
        DeviceDescriptor(
            name: try deviceName(for: deviceID),
            inputChannels: try channelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput),
            outputChannels: try channelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        )
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementWildcard
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )
        try check(status: status, operation: "Read stream configuration size")

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        try check(status: status, operation: "Read stream configuration")

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    private static func deviceName(for deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        try check(status: status, operation: "Read device name")

        return (name as String?) ?? "Unknown Input"
    }

    private static func check(status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw SubtitleError.audioSetupFailed("\(operation) failed (OSStatus: \(status)).")
        }
    }

    private struct DeviceDescriptor {
        let name: String
        let inputChannels: Int
        let outputChannels: Int
    }
}
