import AppKit

/// SwiftUI's `App` covers scenes; a few things still need the AppKit lifecycle.
/// Right now that is only the debug self-tests, which must run after the app has
/// finished launching so AVFoundation is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let test = SelfTest.requested {
            Task { await SelfTest.run(test) }
        }
        #endif
    }
}
