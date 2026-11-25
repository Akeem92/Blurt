import CoreAudio
import OSLog

/// Turns the output volume down for the length of a dictation, and back up after.
///
/// This replaced an attempt to *pause* whatever was playing, which failed for a
/// reason worth recording. Pressing the play/pause key is easy; knowing whether
/// anything is actually playing is not. CoreAudio's
/// `kAudioProcessPropertyIsRunningOutput` reports whether a process holds an
/// output stream open, not whether sound is coming out of it — so a messaging
/// app that keeps a stream open forever, and a *paused* video, both report
/// themselves as playing. Acting on that reading pressed play/pause on a paused
/// video and started it.
///
/// Telling the two apart needs the system audio recording permission, which is
/// far too alarming a thing to ask of a dictation app.
///
/// Lowering the volume sidesteps the question entirely: there is nothing to
/// detect, so there is nothing to get wrong. It cannot start anything, it works
/// with sources that ignore the media keys, and it is what macOS does for Siri.
/// The cost is honest — a podcast keeps talking, quietly.
@MainActor
final class AudioDucking {
    private let log = Logger(subsystem: "com.blurt.app", category: "audio")

    /// Where the volume goes while you speak. Low enough to talk over, not zero:
    /// silence makes people think their music stopped.
    var duckedLevel: Float = 0.1

    /// The level to put back, set only while ducked.
    private var restoreTo: Float?

    /// What was actually set, so a volume the user changed themselves can be
    /// told apart from the one we left behind.
    private var leftAt: Float?

    var isDucked: Bool { restoreTo != nil }

    func duck() {
        guard restoreTo == nil else { return }
        guard let device = Self.defaultOutputDevice(),
              let current = Self.volume(of: device)
        else {
            log.debug("No controllable output device; leaving the volume alone")
            return
        }

        // Already quieter than we would make it. Touching it could only make
        // things worse, and would then "restore" it louder than it was.
        guard current > duckedLevel else { return }

        guard Self.setVolume(duckedLevel, on: device) else {
            log.debug("Output volume is not settable on this device")
            return
        }
        restoreTo = current
        leftAt = duckedLevel
    }

    func restore() {
        guard let restoreTo else { return }
        defer {
            self.restoreTo = nil
            self.leftAt = nil
        }
        guard let device = Self.defaultOutputDevice() else { return }

        // If the volume is no longer where we left it, the user moved it while
        // we were ducked. Their choice wins; putting the old level back would
        // undo a deliberate action.
        if let leftAt, let current = Self.volume(of: device), abs(current - leftAt) > 0.02 {
            log.notice("Volume was changed while ducked; leaving it as the user set it")
            return
        }

        _ = Self.setVolume(restoreTo, on: device)
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return nil }

        return device
    }

    /// Main first, then the individual channels.
    ///
    /// Not every device exposes a main volume — some only have per-channel
    /// controls, and reading only the main one would make Blurt decide the
    /// device has no volume at all.
    private static let volumeElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain, 1, 2,
    ]

    private static func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    static func volume(of device: AudioObjectID) -> Float? {
        for element in volumeElements {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }

            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    @discardableResult
    static func setVolume(_ value: Float, on device: AudioObjectID) -> Bool {
        var succeeded = false

        for element in volumeElements {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }

            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue
            else { continue }

            var level = Float32(min(max(value, 0), 1))
            guard AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level
            ) == noErr else { continue }

            succeeded = true
            // The main control covers every channel, so there is nothing left
            // to set once it has worked.
            if element == kAudioObjectPropertyElementMain { break }
        }
        return succeeded
    }

    /// The current output volume, for diagnostics and tests.
    static func currentVolume() -> Float? {
        defaultOutputDevice().flatMap(volume(of:))
    }
}
