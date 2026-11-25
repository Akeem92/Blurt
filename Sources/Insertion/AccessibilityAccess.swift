import ApplicationServices
import AppKit

/// Whether macOS will let Blurt send keystrokes to other apps.
///
/// This is the permission that makes dictation land anywhere. Without it Blurt
/// can hear and transcribe, but has no way to put the result where the cursor is.
enum AccessibilityAccess {
    /// Granted or not. Cheap, and safe to call repeatedly.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show its "allow Blurt to control your computer" alert.
    ///
    /// Shown only once per app signature per login. Afterwards it does nothing
    /// and returns the current answer, which is why `openSystemSettings()` has
    /// to exist as the way back from a refusal.
    @discardableResult
    @MainActor
    static func requestIfNeeded() -> Bool {
        // The constant is a global `var` in the C header, so Swift 6 refuses to
        // read it from just anywhere. Spelling the key out avoids the global
        // entirely; its value is fixed API, not something that can drift.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openSystemSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
