import SwiftUI

/// The floating indicator shown while Blurt is listening.
///
/// Reads the level meter on its own clock rather than being pushed to — the same
/// arrangement as the settings level bar, so a busy audio pipeline can never
/// make the waveform stutter.
struct RecordingPill: View {
    let controller: DictationController

    /// Rolling history of recent levels, oldest first. Fixed length, so the
    /// waveform scrolls rather than growing.
    @State private var history = [Float](repeating: 0, count: Layout.barCount)

    enum Layout {
        static let barCount = 16
        static let barWidth: CGFloat = 2
        // Tighter than the bars are wide. Narrowing the gaps rather than
        // dropping bars keeps the waveform's resolution — the same stretch of
        // time is still shown, just more compactly.
        static let barGap: CGFloat = 1

        /// The window is this size always; the capsule inside hugs its content
        /// and grows as text arrives. Resizing a borderless panel while it is on
        /// screen is visibly jerky, and there is nothing to gain from it — the
        /// window is transparent and passes clicks through either way.
        static let windowSize = CGSize(width: 560, height: 56)

        static var waveformWidth: CGFloat {
            CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        }
    }

    private var transcript: String {
        controller.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Waveform(samples: history)
                .frame(width: Layout.waveformWidth, height: 12)

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // Truncate the beginning, not the end: the words that just
                    // left your mouth are the ones worth seeing.
                    .truncationMode(.head)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Solid black rather than a material: the pill sits over whatever the
        // user is working in, and a translucent one borrows that background,
        // changing appearance from one app to the next. Black is the same
        // everywhere, which is what makes it read as part of the system rather
        // than part of the window behind it.
        .background {
            Capsule().fill(.black)
            Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.18), value: transcript.isEmpty)
        .frame(width: Layout.windowSize.width, height: Layout.windowSize.height)
        .task {
            // Pulls one sample per displayed frame for as long as this view is on
            // screen, and stops on its own when it goes away.
            while !Task.isCancelled {
                history.removeFirst()
                history.append(controller.inputLevel)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}

/// Rolling bar waveform.
///
/// `Canvas` rather than a stack of 26 shapes: this redraws thirty times a second,
/// and asking SwiftUI to diff a view hierarchy that often to move some rectangles
/// is work for nothing.
private struct Waveform: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let step = RecordingPill.Layout.barWidth + RecordingPill.Layout.barGap
            let minimum: CGFloat = 2

            for (index, sample) in samples.enumerated() {
                // Newest sample on the right, so the waveform scrolls leftwards.
                let x = CGFloat(index) * step
                let height = max(minimum, CGFloat(sample) * size.height)
                let rect = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: RecordingPill.Layout.barWidth,
                    height: height
                )

                // Older samples fade out, which reads as motion even in silence.
                // White, not the accent colour: on black it is the only choice
                // that stays legible whatever the user's accent colour is.
                let age = Double(index) / Double(max(samples.count - 1, 1))
                context.fill(
                    Path(roundedRect: rect, cornerRadius: RecordingPill.Layout.barWidth / 2),
                    with: .color(.white.opacity(0.35 + 0.65 * age))
                )
            }
        }
    }
}
