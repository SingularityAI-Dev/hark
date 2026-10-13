import CoreAudio

/// Silences the default output device while dictating, so music or a video is neither a
/// distraction nor picked up by the microphone, then puts it back as it was.
final class OutputMuter {
    /// The device this object muted. Nil when there is nothing to undo, which is also the
    /// case when the output was already muted before dictation started.
    private var mutedDevice: AudioDeviceID?

    func mute() {
        guard mutedDevice == nil, let device = Self.defaultOutputDevice(),
            Self.isMuted(device) == false, Self.setMuted(true, on: device)
        else { return }
        mutedDevice = device
    }

    func restore() {
        guard let device = mutedDevice else { return }
        mutedDevice = nil
        Self.setMuted(false, on: device)
    }

    /// False for outputs with no mute control of their own, such as some HDMI displays.
    static var isSupported: Bool {
        defaultOutputDevice().flatMap(isMuted) != nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// Nil when the device has no mute control.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
