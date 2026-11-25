import AppKit

/// SwiftUI's `App` covers scenes; a few things still need the AppKit lifecycle.
///
/// The dictation controller lives here rather than as `@State` in `BlurtApp`
/// because things that are not scenes need to reach it. The recording pill is
/// the first: it has to appear while no window of Blurt's is open, so it cannot
/// hang off a view hierarchy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()

    private var pill: RecordingPillPresenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let test = SelfTest.requested {
            Task { await SelfTest.run(test) }
            return
        }
        #endif

        pill = RecordingPillPresenter(controller: controller)
    }
}
