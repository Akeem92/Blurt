import Synchronization

/// One number, shared between the audio thread and the main actor.
///
/// The audio thread writes the latest input level; the UI reads it at screen
/// refresh rate. The two run at completely different rates on purpose, so the
/// waveform stays smooth no matter what the audio pipeline is doing.
///
/// `Atomic` rather than a lock: a lock-free store compiles to a single
/// instruction and can never block. On an audio thread, blocking on a lock held
/// by a lower-priority thread is the classic way to drop a buffer — a glitch you
/// hear but cannot reproduce on demand.
///
/// `Float` has no atomic form of its own, so its bit pattern travels as `UInt32`
/// and is reinterpreted on the way out. Lossless, and the usual trick.
///
/// `.relaxed` ordering is deliberate: this value guards nothing else, so no
/// memory barrier is needed. A reader that misses one update by a frame is
/// showing a 16 ms stale level, which nobody can perceive.
final class AudioLevelMeter: Sendable {
    private let storage = Atomic<UInt32>(Float.zero.bitPattern)

    /// Called from the audio thread. Never blocks, never allocates.
    func store(_ level: Float) {
        storage.store(level.bitPattern, ordering: .relaxed)
    }

    /// Called from the main actor, once per displayed frame.
    func load() -> Float {
        Float(bitPattern: storage.load(ordering: .relaxed))
    }
}
