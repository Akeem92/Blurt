# Blurt

**Hold a key, talk, let go. The text appears wherever your cursor is.**

Blurt is a dictation app for macOS that lives in your menu bar. It works in any
app — your editor, your browser, Slack, the Terminal — and everything happens on
your Mac. No account, no sign-up, no subscription, and it works on a plane.

A free and open alternative to Wispr Flow, and a cousin of
[Handy](https://handy.computer/).

---

## Why you might want it

Typing is slow. Most people speak three or four times faster than they type, and
a lot of what we write all day is not prose worth crafting — it is a message, a
commit description, a reply, a note to yourself.

Dictation already solves this. The problem is what it costs you:

- **The good ones are subscriptions.** Ten to fifteen euros a month, forever, for
  a keyboard shortcut and a text field.
- **They send your voice to a server.** Everything you dictate — meeting notes,
  passwords read aloud by mistake, things about colleagues — travels to someone
  else's computer and is kept under terms you did not negotiate.
- **The built-in one is awkward.** macOS dictation exists, but you have to click
  into a text field first, it has its own ideas about punctuation, and it is not
  really designed for talking to your computer all day.

The speech models that make good dictation possible now run comfortably on an
Apple Silicon Mac. So the monthly fee is buying you a hotkey. Blurt is that
hotkey.

## What it does

**Dictate anywhere.** Hold ⌥Space from any app, speak, let go. The text is typed
where your cursor is. Hold-to-talk or press-to-toggle, and the shortcut is yours
to change.

**See what it hears.** A small pill appears at the bottom of the screen with a
live waveform and the text as it is being recognised, so you know it is working
and can stop if it goes astray. It never steals focus from what you were doing.

**Punctuation, done for you.** Full stops and commas appear where they belong.
Say "comma" or "new line" and you get one. French gets its proper typography —
the non-breaking space before `; ! ? :` that nothing else bothers with.

**Gets out of the way.** Music or a video is turned down while you speak and
comes back up afterwards, the way macOS does for Siri.

**Leaves your clipboard alone.** Text is inserted through the clipboard, and
whatever you had copied — including images and files — is put straight back.

**Tidies up, if you want.** Filler sounds like "um" and "euh" are removed
automatically. Optionally, Claude can apply spoken corrections — say "send it to
Marc, no sorry, to Julie" and you get Julie — using an API key you provide.

## Your voice stays yours

This is the part worth being precise about.

| | |
|---|---|
| **Audio** | Never written to disk. It goes from the microphone to the transcriber in memory and is gone when the dictation ends. |
| **Transcription** | Entirely on your Mac, using Apple's on-device speech models. Works offline. |
| **Your text** | Kept in memory until the next dictation, forgotten when Blurt quits. Nothing is logged. |
| **Settings** | Stored locally. They contain no dictated content. |
| **API key** | In the macOS Keychain, encrypted — if you choose to use one. |

The one exception is clearly marked: **if you turn on cleanup through Claude,
the transcribed text is sent to Anthropic** to be tidied. Never the audio, and
only while that setting is on. It is off by default and the app is fully usable
without it. The Settings window tells you which of the two situations you are
in.

## Requirements

- **macOS 26 or later**, on **Apple Silicon**. Apple's on-device speech
  framework sets that floor.
- A microphone. The built-in one is fine — often better than a headset's, which
  tends to be quiet.
- Optionally, an [Anthropic API key](https://console.anthropic.com) for the
  cleanup pass. It costs a fraction of a cent per dictation.

## Installing

There is no packaged download yet, so Blurt is built from source. You will need
[Xcode](https://developer.apple.com/xcode/) and a free Apple Developer account.

```sh
git clone https://github.com/Akeem92/Blurt.git
cd Blurt
brew install xcodegen
xcodegen generate
open Blurt.xcodeproj
```

Then press ▶ in Xcode.

**One thing to set up first.** macOS ties the permission that lets Blurt type
into other apps to the app's code signature. An improvised signature changes
every time you build, so macOS treats each build as a different app and asks for
the permission again — every single time. Point it at your own certificate once
and the permission sticks.

Create `Signing.local.xcconfig` next to `project.yml`. It is ignored by git, so
your identity never ends up in a public repository:

```
CODE_SIGN_IDENTITY = <the SHA-1 from the command below>
DEVELOPMENT_TEAM = <your ten-character team id>
```

```sh
security find-identity -v -p codesigning
```

The ten characters in parentheses are your team id.

## Keeping it

Running from Xcode puts the app somewhere deep in `DerivedData` and it goes away
when you clean the project. To keep Blurt around like any other app, build a
release copy and move it to your Applications folder:

```sh
xcodebuild -project Blurt.xcodeproj -scheme Blurt \
           -configuration Release -derivedDataPath build build

cp -R build/Build/Products/Release/Blurt.app /Applications/
open /Applications/Blurt.app
```

Or, in Xcode: switch the scheme to Release, build, then **Product → Show Build
Folder in Finder** and drag `Blurt.app` into Applications.

**You will not have to grant the permissions again.** macOS recognises an app by
its code signature rather than by where it sits on disk, so as long as it is
signed with the same certificate, the microphone and accessibility permissions
you granted while developing follow the copy. This is the reason the signing
step above is worth doing properly.

Finally, open **Settings… → General** and turn on **Launch Blurt at login**. It
will be in the menu bar every time you log in, which is when a dictation app
stops being something you remember to open and starts being something you use.

The release build is about 1.7 MB and has no debug tooling in it — the
self-tests below exist only in debug builds.

## First run

Blurt appears in the menu bar as a waveform icon — there is no Dock icon and no
window. Open **Settings…** from its menu and work through two permissions:

1. **Microphone** — so it can hear you.
2. **Accessibility** (under *Insertion*) — so it can type into other apps.
   Without it Blurt still transcribes, but the text has nowhere to go.

Then pick your language under **Transcription**. The model downloads once, after
which everything works offline. One language at a time: the model cannot switch
mid-sentence, so choose the one you actually dictate in, which is not always the
language your Mac is set to.

That is it. Hold ⌥Space anywhere and speak.

## Built with

Entirely native, with a single dependency.

- **Swift 6 and SwiftUI**, with strict concurrency checking.
- **`SpeechAnalyzer` / `DictationTranscriber`** — Apple's on-device speech
  models, tuned for dictation rather than general transcription. They are what
  bring automatic punctuation, spoken punctuation and emoji by name.
- **AVAudioEngine** for microphone capture, **CoreAudio** for turning other
  audio down.
- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)**
  (MIT) for the global shortcut. It wraps Carbon's `RegisterEventHotKey`, which
  needs no permission and keeps working while a password field is focused —
  unlike an event tap, which goes silent in that state.
- **Claude Haiku**, optionally, for the cleanup pass.
- **XcodeGen**, so the project is a readable `project.yml` rather than an opaque
  binary file.

## Self-tests

Audio behaviour does not show up at compile time or at launch — it surfaces the
first time someone actually speaks. The debug build therefore carries headless
checks that can be run without clicking anything:

```sh
B=Blurt.app/Contents/MacOS/Blurt

$B --selftest-capture      # the audio thread survives real buffers
$B --selftest-record       # capture through to a playable file
$B --selftest-transcribe   # speaks a known sentence, checks the words come back
$B --selftest-shortcut     # both activation modes, including a brushed key
$B --selftest-pill         # the pill never takes focus
$B --selftest-clipboard    # the clipboard is borrowed and given back intact
$B --selftest-media        # the volume ducks and comes back
$B --selftest-cleanup      # the cleanup rules, including French typography
$B --selftest-mic          # a bench: records from your microphone and reports
```

The last one is not a pass/fail check but a bench. Transcription quality cannot
be judged from an impression after the fact, because every attempt says
something different in a different voice. It records the same sentence under one
changed setting at a time and reports the input level, whether the model
finalised, and what it heard.

Between them these have caught a crash on the first audio buffer, transcripts
that came back empty, a microphone left open indefinitely, a shortcut that
stopped responding after a failure, a dictation wedged forever on
"Transcribing…", a clipboard overwritten and never restored, and an entire
dictation written out twice.

## Licence

MIT. See [LICENSE](LICENSE).
