import CoreAudio
import DesktopControlCore
import Foundation

/// Reads and controls the default audio output through CoreAudio. Needs no permission.
final class CoreAudioOutputController: AudioControlling {
    var onChange: (() -> Void)?

    private var system: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }
    private var watchedDevice: AudioObjectID = 0
    private var started = false
    private var blocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        startListening()
    }

    deinit {
        for (object, address, block) in blocks {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
    }

    // MARK: - AudioControlling

    func state() -> AudioOutputState {
        let device = defaultOutput()
        let kind = kind(of: device)
        return AudioOutputState(
            deviceName: name(of: device) ?? "Unknown",
            kind: kind,
            volume: volume(of: device),
            muted: muted(of: device),
            available: outputDevices().compactMap { name(of: $0) })
    }

    @discardableResult
    func setVolume(_ percent: Int) -> Bool {
        let device = defaultOutput()
        let value = Float32(min(100, max(0, percent))) / 100
        if let address = volumeAddress(device), isSettable(device, address) {
            return set(device, address, value)
        }
        // Per-channel fallback (left/right) for devices without a main volume.
        var any = false
        for channel in [AudioObjectPropertyElement(1), 2] {
            let address = property(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel)
            if has(device, address), isSettable(device, address) { any = set(device, address, value) || any }
        }
        return any
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        let device = defaultOutput()
        guard let address = muteAddress(device), isSettable(device, address) else { return false }
        return set(device, address, UInt32(muted ? 1 : 0))
    }

    @discardableResult
    func selectOutput(named name: String) -> Bool {
        guard let target = outputDevices().first(where: { self.name(of: $0) == name }) else { return false }
        return set(system, property(kAudioHardwarePropertyDefaultOutputDevice), target)
    }

    // MARK: - Reading

    private func defaultOutput() -> AudioObjectID {
        get(system, property(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? 0
    }

    private func name(of device: AudioObjectID) -> String? {
        guard device != 0 else { return nil }
        var address = property(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func kind(of device: AudioObjectID) -> AudioOutputKind {
        guard device != 0, let transport: UInt32 = get(device, property(kAudioDevicePropertyTransportType), UInt32(0)) else {
            return .other
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // Built-in output: speaker or headphone jack.
            let source: UInt32? = get(
                device, property(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput), UInt32(0))
            return source == fourCC("hdpn") ? .headphones : .builtinSpeaker
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .hdmi
        case kAudioDeviceTransportTypeAirPlay: return .airplay
        default: return .other
        }
    }

    private func volume(of device: AudioObjectID) -> Int? {
        guard device != 0 else { return nil }
        if let address = volumeAddress(device), let value: Float32 = get(device, address, Float32(0)) {
            return Int((value * 100).rounded())
        }
        var values: [Float32] = []
        for channel in [AudioObjectPropertyElement(1), 2] {
            let address = property(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel)
            if has(device, address), let value: Float32 = get(device, address, Float32(0)) { values.append(value) }
        }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Float32(values.count) * 100).rounded())
    }

    private func muted(of device: AudioObjectID) -> Bool? {
        guard device != 0, let address = muteAddress(device), let value: UInt32 = get(device, address, UInt32(0)) else { return nil }
        return value != 0
    }

    /// Virtual main volume ('vmvc') is the value the macOS volume slider uses.
    private func volumeAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        for selector in [fourCC("vmvc"), kAudioDevicePropertyVolumeScalar] {
            let address = property(selector, scope: kAudioObjectPropertyScopeOutput)
            if has(device, address) { return address }
        }
        return nil
    }

    private func muteAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        let address = property(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return has(device, address) ? address : nil
    }

    private func outputDevices() -> [AudioObjectID] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { device in
            var streams = property(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return false }
            let hidden: UInt32 = get(device, property(kAudioDevicePropertyIsHidden), UInt32(0)) ?? 0
            return hidden == 0
        }
    }

    // MARK: - Listening

    private func startListening() {
        guard !started else { return }
        started = true
        listen(system, property(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.watchDefaultDevice()
            self?.onChange?()
        }
        listen(system, property(kAudioHardwarePropertyDevices)) { [weak self] in self?.onChange?() }
        watchDefaultDevice()
    }

    /// Volume, mute and data source live on the current default device, so re-attach on every switch.
    private func watchDefaultDevice() {
        blocks.removeAll { entry in
            guard entry.0 == watchedDevice, entry.0 != system else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2)
            return true
        }
        watchedDevice = defaultOutput()
        guard watchedDevice != 0 else { return }
        for selector in [fourCC("vmvc"), kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute, kAudioDevicePropertyDataSource] {
            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                listen(watchedDevice, property(selector, scope: kAudioObjectPropertyScopeOutput, element: element)) { [weak self] in
                    self?.onChange?()
                }
            }
        }
    }

    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            blocks.append((object, address, block))
        }
    }

    // MARK: - Helpers

    private func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    private func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    private func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
