import AppKit

/// SwiftUI's `App` covers scenes; a few things still need the AppKit lifecycle.
///
/// The long-lived objects live here rather than as `@State` in `BlurtApp`,
/// because things that are not scenes need to reach them. The recording pill has
/// to appear while no window of Blurt's is open, and the shortcut has to work
/// when the app has no window at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    lazy var controller = DictationController(preferences: preferences)

    private var pill: RecordingPillPresenter?
    private var shortcut: ShortcutCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let test = SelfTest.requested {
            Task { await SelfTest.run(test) }
            return
        }
        #endif

        pill = RecordingPillPresenter(controller: controller)
        shortcut = ShortcutCoordinator(controller: controller, preferences: preferences)
    }
}
