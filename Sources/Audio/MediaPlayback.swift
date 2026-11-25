import CoreAudio
import AppKit
import OSLog

/// Pauses whatever is playing while you dictate, and starts it again afterwards.
///
/// Two problems, not one. Pressing play/pause is easy; knowing whether anything
/// was playing is the hard part, and skipping it would mean a dictation started
/// in silence *starts* music that was never running — which is worse than doing
/// nothing at all.
///
/// Detection goes through CoreAudio's per-process objects (macOS 14.2+), which
/// report which processes are currently producing output. That covers every
/// player at once — Music, Spotify, a video in a browser tab — without knowing
/// anything about any of them.
@MainActor
final class MediaPlayback {
    private let log = Logger(subsystem: "com.blurt.app", category: "media")

    /// True only between a pause we performed and the resume that undoes it.
    /// Nothing is ever resumed that Blurt did not pause.
    private(set) var didPause = false

    /// Pauses playback if something is audibly playing. Does nothing otherwise.
    func pauseIfPlaying() {
        guard !didPause else { return }
        guard Self.isAnythingPlaying() else {
            log.debug("Nothing playing; leaving the keyboard alone")
            return
        }
        Self.pressPlayPause()
        didPause = true
    }

    /// Resumes only what this object paused.
    func resumeIfPaused() {
        guard didPause else { return }
        didPause = false
        Self.pressPlayPause()
    }

    // MARK: - Is anything playing?

    /// Whether any process other than Blurt is currently producing audio output.
    /// Internal rather than private so a self-test can exercise it: this is the
    /// half that is hard to get right.
    static func isAnythingPlaying() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for process in audioProcesses() {
            guard let pid: pid_t = property(of: process, selector: kAudioProcessPropertyPID),
                  pid != ownPID
            else { continue }

            if let running: UInt32 = property(of: process, selector: kAudioProcessPropertyIsRunningOutput),
               running != 0 {
                return true
            }
        }
        return false
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects
    }

    /// Reads one fixed-size property off an audio object.
    private static func property<T>(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        var value: T?

        let status = withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer -> OSStatus in
            let status = AudioObjectGetPropertyData(
                object, &address, 0, nil, &size, buffer.baseAddress!
            )
            if status == noErr { value = buffer[0] }
            return status
        }
        return status == noErr ? value : nil
    }

    // MARK: - The keystroke

    /// Presses the play/pause key, as the hardware key on the keyboard does.
    ///
    /// Not a normal key event: media keys travel as system-defined events with a
    /// payload describing which key and whether it went down or up. Every player
    /// that honours the keyboard's play button honours this, which is why it is
    /// preferred over scripting each app by name.
    ///
    /// Requires accessibility permission — the same one that lets Blurt paste,
    /// so it costs nothing extra by the time this runs.
    private static func pressPlayPause() {
        let playKey: Int32 = 16  // NX_KEYTYPE_PLAY

        for isDown in [true, false] {
            let state: Int32 = isDown ? 0xA : 0xB
            let data1 = Int((playKey << 16) | (state << 8))

            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }

            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
