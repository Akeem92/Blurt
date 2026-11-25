# Blurt

Hold a key, talk, let go. The text lands wherever your cursor is.

Blurt is a menu-bar dictation app for macOS. Transcription runs **on your Mac** —
no account, no server, no upload, and it works on a plane. An optional cleanup
pass can polish the result through Claude if you bring your own API key, but the
app is fully usable without ever touching the network.

It is a free, open alternative to Wispr Flow and a cousin of
[Handy](https://handy.computer/).

> **Status: usable.** Hold the shortcut, speak, let go — the text lands where
> your cursor is. Cleanup and the fuller settings are still to come.
> See [Roadmap](#roadmap).

## Why

Good dictation is a solved problem that is mostly sold as a subscription. The
models that make it work now run comfortably on an Apple Silicon Mac, so the
monthly fee buys you a hotkey and a text field. Blurt is that hotkey and that
text field.

## Requirements

- macOS 26 or later — Apple's `SpeechAnalyzer` framework is macOS 26+.
  Support for older systems arrives with the Parakeet and Whisper engines, which
  have no such floor.
- Apple Silicon.

## Roadmap

| Step | What it adds | Status |
|-----:|--------------|--------|
| 1 | Menu-bar skeleton, settings window, state machine | ✅ done |
| 2a | Microphone permission, capture, live input level | ✅ done |
| 2b | The floating recording pill | ✅ done |
| 3 | Configurable global shortcut, hold-to-talk and toggle | ✅ done |
| 4 | On-device transcription, live in the pill | ✅ done |
| 5 | Insertion into the frontmost app, pausing other audio | ✅ done |
| 6 | Cleanup: punctuation and fillers, optional Claude polish | — |
| 7 | Full settings: colours, languages, history, custom dictionary | — |

Later: Parakeet and Whisper engines, per-app writing styles, a personal
dictionary for names and jargon, voice commands over selected text.

## Details that matter

Dictation lives or dies on small courtesies. These are tracked as features, not
polish:

- **Get out of the way of whatever is playing.** Music or a video pauses for the
  length of a dictation and starts again afterwards. Blurt asks CoreAudio which
  processes are actually producing output before pressing anything, so a
  dictation in silence never *starts* music that was not running — and it only
  resumes what it paused itself. Every route out of a dictation, errors included,
  goes through one place, so none of them can leave your music paused.
- **Never steal focus.** The recording pill is a non-activating panel. The moment
  an overlay takes focus, the app that was supposed to receive the text is no
  longer frontmost and the dictation has nowhere to land.
- **Borrow the clipboard, never confiscate it.** Insertion goes through the
  clipboard, so its previous contents are saved and put back — images and files
  included, not just text. When pasting is not possible, the clipboard is left
  untouched rather than overwritten: it may hold the only copy of something.
- **Never lose words.** A dictation that cannot be inserted is still in the menu
  under Copy Last Dictation.

## Design notes

**One explicit state machine.** A dictation moves through `idle → recording →
transcribing → cleaning → inserting`. That lives in a single `RecordingState`
enum where each case carries exactly its own data, so states that contradict each
other cannot be written down at all. The menu-bar icon reads that enum directly.

**Engines behind protocols.** Transcription and cleanup are each defined by a
protocol with interchangeable implementations, so adding Parakeet or swapping the
cleanup model touches one file and nothing else.

**Local first.** Every default keeps audio on the machine. The Claude cleanup
step is opt-in, needs a key you supply, and sends text only — never audio.

## Building

```sh
brew install xcodegen
xcodegen generate
open Blurt.xcodeproj
```

`project.yml` is the source of truth for the project. `Blurt.xcodeproj/`,
`Support/Info.plist` and `Support/Blurt.entitlements` are generated from it and
are not tracked in git — re-run `xcodegen generate` after adding files or
changing build settings.

**Signing matters more than usual here.** macOS binds the Accessibility
permission to an app's code signature, so an ad-hoc signature — which changes on
every build — means re-granting it after every build. Create
`Signing.local.xcconfig` (git-ignored) with your own certificate:

```
CODE_SIGN_IDENTITY = <SHA-1 from `security find-identity -v -p codesigning`>
DEVELOPMENT_TEAM = <your ten-character team id>
```

### Self-tests

Behaviour that only appears once real audio is flowing does not show up at
compile time, so the debug build carries headless checks:

```sh
Blurt.app/Contents/MacOS/Blurt --selftest-capture      # the audio thread
Blurt.app/Contents/MacOS/Blurt --selftest-record       # capture to a playable file
Blurt.app/Contents/MacOS/Blurt --selftest-transcribe   # speaks a known sentence, checks the words
Blurt.app/Contents/MacOS/Blurt --selftest-shortcut     # both activation modes
Blurt.app/Contents/MacOS/Blurt --selftest-pill         # the pill never takes focus
Blurt.app/Contents/MacOS/Blurt --selftest-clipboard    # the clipboard round trip
Blurt.app/Contents/MacOS/Blurt --selftest-media        # playback detection
```

Between them they have caught a crash on the first audio buffer, empty
transcripts, a microphone left open for good, a shortcut that died after a
failure, a dictation wedged forever on "Transcribing…", and a clipboard that was
overwritten and never restored.

## Licence

MIT. See [LICENSE](LICENSE).
