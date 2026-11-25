import SwiftUI

/// The floating indicator shown while Blurt is listening.
///
/// Reads the level meter on its own clock rather than being pushed to — the same
/// arrangement as the settings level bar, so a busy audio pipeline can never
/// make the waveform stutter.
struct RecordingPill: View {
    let meter: AudioLevelMeter

    /// Rolling history of recent levels, oldest first. Fixed length, so the
    /// waveform scrolls rather than growing.
    @State private var history = [Float](repeating: 0, count: Layout.barCount)

    enum Layout {
        static let barCount = 26
        static let barWidth: CGFloat = 3
        static let barGap: CGFloat = 2
        static let size = CGSize(width: 168, height: 42)
        static var waveformWidth: CGFloat {
            CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)

            Waveform(samples: history)
                .frame(width: Layout.waveformWidth, height: 20)
        }
        .padding(.horizontal, 14)
        .frame(width: Layout.size.width, height: Layout.size.height)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
        .task {
            // Pulls one sample per displayed frame for as long as this view is on
            // screen, and stops on its own when it goes away.
            while !Task.isCancelled {
                history.removeFirst()
                history.append(meter.load())
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
            let minimum: CGFloat = 3

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
                let age = Double(index) / Double(max(samples.count - 1, 1))
                context.fill(
                    Path(roundedRect: rect, cornerRadius: RecordingPill.Layout.barWidth / 2),
                    with: .color(.accentColor.opacity(0.35 + 0.65 * age))
                )
            }
        }
    }
}

#Preview {
    RecordingPill(meter: AudioLevelMeter())
        .padding(40)
}
