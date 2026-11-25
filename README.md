# Blurt

Hold a key, talk, let go. The text lands wherever your cursor is.

Blurt is a menu-bar dictation app for macOS. Transcription runs **on your Mac** —
no account, no server, no upload, and it works on a plane. An optional cleanup
pass can polish the result through Claude if you bring your own API key, but the
app is fully usable without ever touching the network.

It is a free, open alternative to Wispr Flow and a cousin of
[Handy](https://handy.computer/).

> **Status: early.** The app records audio and can play it back to you, but it
> does not transcribe anything yet. See [Roadmap](#roadmap).

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
| 4 | Transcription via Apple SpeechAnalyzer | — |
| 5 | Insertion into the frontmost app — **first usable build** | — |
| 6 | Cleanup: punctuation and fillers, optional Claude polish | — |
| 7 | Full settings: colours, languages, history, custom dictionary | — |

Later: Parakeet and Whisper engines, per-app writing styles, a personal
dictionary for names and jargon, voice commands over selected text.

## Details that matter

Dictation lives or dies on small courtesies. These are tracked as features, not
polish:

- **Get out of the way of whatever is playing.** Start a dictation over music or
  a video and the other audio should pause, then resume by itself. Lands with
  step 5: a real pause means simulating the play/pause media key, which needs the
  same Accessibility permission that inserting text does, so it costs nothing
  extra once that permission is in hand. It has to detect what is playing first,
  or it would start music that was never running.
  Apple's voice-processing unit ducks other audio for free, but it is built for
  speakerphone conditions and audibly degrades a headset microphone, so it is not
  the answer here.
- **Never steal focus.** The recording pill has to be a non-activating panel.
  The moment the overlay takes focus, the app that was supposed to receive the
  text is no longer frontmost and the dictation has nowhere to land.
- **Leave the clipboard as you found it.** Insertion goes through the clipboard,
  so whatever was in it is saved and put back afterwards.
- **Never lose words.** A failure anywhere after transcription still leaves the
  text somewhere reachable — the clipboard, or the history.

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

`project.yml` is the source of truth for the project. `Blurt.xcodeproj/` and
`Support/Info.plist` are generated from it and are not tracked in git — re-run
`xcodegen generate` after adding files or changing build settings.

## Licence

MIT. See [LICENSE](LICENSE).
