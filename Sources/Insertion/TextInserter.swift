import AppKit
import OSLog

/// Puts finished text wherever the cursor is.
///
/// A protocol for the same reason transcription has one: there is more than one
/// way to do this and they suit different apps. The clipboard route works
/// everywhere; writing through the accessibility API directly is tidier but
/// fails in Electron apps and terminals, which is most of where people type.
protocol TextInserter: Sendable {
    func insert(_ text: String) async throws
}

/// Inserts by putting the text on the clipboard and pressing ⌘V.
///
/// Crude-sounding, and the only approach that genuinely works everywhere —
/// native apps, Electron, terminals, web views alike. It is what Wispr Flow,
/// Handy and Raycast all do.
///
/// The clipboard belongs to the user, so it is borrowed and given back: whatever
/// was in it is saved first and restored afterwards, with its types intact, so a
/// copied image or file is not quietly replaced by a sentence.
@MainActor
final class ClipboardInserter: TextInserter {
    private let log = Logger(subsystem: "com.blurt.app", category: "insertion")

    /// How long to leave the text on the clipboard before putting the old
    /// contents back.
    ///
    /// ⌘V is delivered asynchronously: the keystroke is posted, the frontmost
    /// app notices it, and only then does it read the clipboard. Restoring
    /// immediately wins that race and pastes the user's previous clipboard
    /// instead of the dictation.
    private static let pasteWindow = Duration.milliseconds(120)

    func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }

        // Checked before the clipboard is touched at all, not after.
        //
        // The tempting alternative — leave the text on the clipboard so the user
        // can paste it themselves — destroys whatever they had copied, which may
        // be an image or a file that no longer exists anywhere else. Borrowing
        // the clipboard is only acceptable when it is about to be given back.
        // The words are not lost either way: they stay in the last dictation,
        // and the menu offers to copy them deliberately.
        guard AccessibilityAccess.isTrusted else {
            log.notice("No accessibility permission; leaving the clipboard alone")
            throw DictationError.accessibilityPermissionDenied
        }

        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Self.pressCommandV()

        try? await Task.sleep(for: Self.pasteWindow)
        Self.restore(saved, to: pasteboard)
    }

    // MARK: - Keystroke

    /// Synthesises ⌘V.
    ///
    /// The event source is `.privateState` on purpose. A source tied to the
    /// session carries whatever modifiers are physically held at that moment,
    /// and in hold-to-talk the user may still have a finger on Option as the
    /// key comes up — which would turn this into ⌥⌘V and paste as plain text,
    /// or nothing at all. A private source starts from no modifiers, so the
    /// event is exactly the one described here.
    private static func pressCommandV() {
        let source = CGEventSource(stateID: .privateState)
        let v: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Borrowing the clipboard

    /// Every item on the clipboard, with every representation it carries.
    ///
    /// Copied out as raw data rather than held as `NSPasteboardItem`s: those
    /// belong to the pasteboard and are emptied by `clearContents()`, so keeping
    /// references would restore nothing.
    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pasteboard.pasteboardItems?.compactMap { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations.isEmpty ? nil : representations
        } ?? []
    }

    private static func restore(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items = snapshot.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
