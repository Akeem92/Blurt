import Foundation
import Observation

/// Settings that outlive a launch.
///
/// Kept deliberately small, and separate from `DictationController`: what the
/// user has chosen is not the same thing as what the app is currently doing, and
/// mixing the two is how settings end up being reset by a state transition.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let activationMode = "activationMode"
        static let voiceProcessing = "voiceProcessingEnabled"
        static let automaticGainControl = "automaticGainControlEnabled"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let punctuation = "punctuationEnabled"
        static let emoji = "emojiEnabled"
    }

    /// The language dictation is transcribed in.
    ///
    /// Chosen explicitly rather than following the system, because the language
    /// someone's Mac is set to and the language they dictate in are routinely
    /// different. The engine transcribes one language at a time and cannot switch
    /// mid-sentence, so this is a real decision rather than a hint.
    var transcriptionLanguage: String {
        didSet { defaults.set(transcriptionLanguage, forKey: Key.transcriptionLanguage) }
    }

    var transcriptionLocale: Locale { Locale(identifier: transcriptionLanguage) }

    /// Automatic punctuation, and punctuation you say out loud. Without it the
    /// transcript is one unbroken run of words.
    var isPunctuationEnabled: Bool {
        didSet { defaults.set(isPunctuationEnabled, forKey: Key.punctuation) }
    }

    /// Turns "smiley face" into an emoji. Off by default — delightful when meant,
    /// startling when not.
    var isEmojiEnabled: Bool {
        didSet { defaults.set(isEmojiEnabled, forKey: Key.emoji) }
    }

    var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Key.activationMode) }
    }

    /// Off by default. Apple's voice processing is built for speakerphone
    /// conditions and audibly thins out a headset microphone.
    var isVoiceProcessingEnabled: Bool {
        didSet { defaults.set(isVoiceProcessingEnabled, forKey: Key.voiceProcessing) }
    }

    var isAutomaticGainControlEnabled: Bool {
        didSet { defaults.set(isAutomaticGainControlEnabled, forKey: Key.automaticGainControl) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        activationMode = defaults.string(forKey: Key.activationMode)
            .flatMap(ActivationMode.init(rawValue:)) ?? .holdToTalk

        isVoiceProcessingEnabled = defaults.bool(forKey: Key.voiceProcessing)

        // `bool(forKey:)` returns false for a key that was never written, which
        // would silently flip the default. Check for the key itself.
        isAutomaticGainControlEnabled = defaults.object(forKey: Key.automaticGainControl) == nil
            ? true
            : defaults.bool(forKey: Key.automaticGainControl)

        // The system language is only the opening suggestion; once chosen, the
        // setting stands on its own.
        transcriptionLanguage = defaults.string(forKey: Key.transcriptionLanguage)
            ?? Locale.current.identifier(.bcp47)

        isPunctuationEnabled = defaults.object(forKey: Key.punctuation) == nil
            ? true
            : defaults.bool(forKey: Key.punctuation)

        isEmojiEnabled = defaults.bool(forKey: Key.emoji)
    }
}
