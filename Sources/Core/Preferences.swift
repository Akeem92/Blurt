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
    }
}
