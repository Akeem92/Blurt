import AVFoundation
import AppKit

/// Whether macOS will let Blurt hear anything, and how to ask if it won't.
enum MicrophoneAccess {
    enum Status {
        /// Never asked. Asking will show the system prompt.
        case undetermined
        /// Granted. The microphone can be opened.
        case granted
        /// Refused, or blocked by policy. Only System Settings can undo this —
        /// asking again does nothing and shows no prompt.
        case denied
    }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .denied
        }
    }

    /// Shows the system prompt, once ever. Returns what the user chose.
    ///
    /// If this returns `false` without any prompt appearing, the usual cause is a
    /// missing `com.apple.security.device.audio-input` entitlement: under the
    /// hardened runtime macOS denies the request outright rather than asking.
    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Opens the Microphone pane of Privacy & Security — the only way back from
    /// `.denied`.
    @MainActor
    static func openSystemSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
