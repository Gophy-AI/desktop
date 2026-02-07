import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

@MainActor
struct RecordingPlayerView: View {
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    @Binding var speed: Float
    let speakerCount: Int
    let onSeek: (TimeInterval) -> Void
    let onTogglePlayback: () -> Void
    let onStop: () -> Void
    let onSpeedChange: (Float) -> Void
    let audioURL: URL?

    private static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var body: some View {
        HStack(spacing: 12) {
            playbackControls

            timeLabel(currentTime)

            waveformSeekBar

            timeLabel(duration)

            speedPicker

            if speakerCount > 0 {
                speakerBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Subviews

    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
    }

    private var waveformSeekBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let url = audioURL {
                    WaveformView(audioURL: url, configuration: waveformConfiguration)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                }

                // Progress overlay
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: geometry.size.width * CGFloat(progress))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Playhead
                if duration > 0 {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(progress))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        let seekTime = Double(fraction) * duration
                        onSeek(seekTime)
                    }
            )
            .accessibilityLabel("Seek to position in recording")
            .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(duration))")
        }
        .frame(height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var waveformConfiguration: Waveform.Configuration {
        Waveform.Configuration(
            size: CGSize(width: 600, height: 32),
            backgroundColor: .clear,
            style: .filled(
                NSColor.secondaryLabelColor.withAlphaComponent(0.4)
            ),
            damping: .init(percentage: 0.125, sides: .both),
            verticalScalingFactor: 0.9
        )
    }

    private var speedPicker: some View {
        Menu {
            ForEach(Self.speedOptions, id: \.self) { rate in
                Button(action: { onSpeedChange(rate) }) {
                    HStack {
                        Text(formatSpeed(rate))
                        if rate == speed {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(formatSpeed(speed))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Playback speed")
        .accessibilityValue(formatSpeed(speed))
    }

    private var speakerBadge: some View {
        Label("\(speakerCount)", systemImage: "person.2")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func timeLabel(_ time: TimeInterval) -> some View {
        Text(formatTime(time))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .center)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatSpeed(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isPlaying = false
        @State private var currentTime: TimeInterval = 45
        @State private var duration: TimeInterval = 180
        @State private var speed: Float = 1.0

        var body: some View {
            RecordingPlayerView(
                isPlaying: $isPlaying,
                currentTime: $currentTime,
                duration: $duration,
                speed: $speed,
                speakerCount: 3,
                onSeek: { _ in },
                onTogglePlayback: { isPlaying.toggle() },
                onStop: {},
                onSpeedChange: { speed = $0 },
                audioURL: nil
            )
            .frame(width: 800)
        }
    }
    return PreviewWrapper()
}
