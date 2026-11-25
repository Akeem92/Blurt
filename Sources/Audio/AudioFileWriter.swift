import AVFoundation

/// Writes captured audio to a CAF file on disk.
///
/// An `actor` because `AVAudioFile` is not thread-safe and disk writes must not
/// happen on the main thread — a stalled write would freeze the interface mid
/// dictation. Isolating the file inside an actor gets both: the compiler enforces
/// one-writer-at-a-time, and the writing runs off the main actor without a queue
/// to hand-manage.
///
/// This exists so step 2 can be judged by ear rather than by a moving bar. Once
/// transcription lands, recording to disk becomes optional.
actor AudioFileWriter {
    private let file: AVAudioFile
    let url: URL

    init(url: URL, format: AVAudioFormat) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Written in the format the microphone delivers, so the file is exactly
        // what the transcriber will later be given — no resampling in between to
        // mask a capture problem.
        self.file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.url = url
    }

    func write(_ captured: CapturedBuffer) throws {
        try file.write(from: captured.buffer)
    }

    /// Where recordings live: `~/Library/Application Support/Blurt/Recordings`.
    ///
    /// Milliseconds are in the name for a reason. Timestamped to the second, two
    /// dictations started within the same second produce the same path and the
    /// first is silently overwritten — which is exactly what a dictation app
    /// invites, since nothing stops anyone speaking twice in quick succession.
    static func newRecordingURL(now: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appending(path: "Blurt/Recordings", directoryHint: .isDirectory)
            .appending(path: "\(formatter.string(from: now)).caf")
    }
}
