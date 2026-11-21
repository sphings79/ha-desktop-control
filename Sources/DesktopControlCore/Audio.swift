import Foundation

/// Kind of the current audio output, as published to Home Assistant.
public enum AudioOutputKind: String, Sendable, CaseIterable {
    case builtinSpeaker = "builtin_speaker"
    case headphones
    case bluetooth
    case usb
    case hdmi
    case airplay
    case other
}

/// Snapshot of the default audio output device.
public struct AudioOutputState: Equatable, Sendable {
    public var deviceName: String
    public var kind: AudioOutputKind
    /// 0...100, nil if the device has no software volume (e.g. HDMI/DisplayPort monitors).
    public var volume: Int?
    /// nil if the device has no mute control.
    public var muted: Bool?
    /// Names of all selectable output devices (includes the current one).
    public var available: [String]

    public init(deviceName: String, kind: AudioOutputKind, volume: Int? = nil, muted: Bool? = nil, available: [String] = []) {
        self.deviceName = deviceName
        self.kind = kind
        self.volume = volume
        self.muted = muted
        self.available = available
    }
}

public protocol AudioControlling: AnyObject {
    /// Called on the main thread when the output device, volume or mute state changes.
    var onChange: (() -> Void)? { get set }
    func state() -> AudioOutputState
    @discardableResult func setVolume(_ percent: Int) -> Bool
    @discardableResult func setMuted(_ muted: Bool) -> Bool
    @discardableResult func selectOutput(named name: String) -> Bool
}
