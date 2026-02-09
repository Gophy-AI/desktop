import SwiftUI
import AVFoundation
import Accelerate

/// Safe waveform loader that reads audio samples directly via AVAudioFile
/// instead of DSWaveformImage's WaveformAnalyzer.
///
/// WaveformAnalyzer internally calls AVAsset.loadTracks() which bridges an ObjC
/// completion handler to Swift async via UnsafeContinuation. This continuation
/// can become dangling when SwiftUI tears down the enclosing view, causing SIGSEGV.
/// AVAudioFile reads synchronously — no continuations, no crash.
@MainActor
private final class WaveformLoader: ObservableObject {
    @Published var samples: [Float] = []
    private var generation: Int = 0

    func load(url: URL, count: Int) {
        generation += 1
        let expectedGeneration = generation
        guard count > 0 else { return }
        Task.detached(priority: .utility) {
            let result = Self.extractSamples(from: url, count: count)
            await MainActor.run { [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.samples = result
            }
        }
    }

    func invalidate() {
        generation += 1
    }

    /// Read audio file synchronously and downsample to `count` amplitude values.
    private nonisolated static func extractSamples(from url: URL, count: Int) -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = AVAudioFrameCount(audioFile.length)
        guard totalFrames > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: totalFrames
        ) else { return [] }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }

        // Take first channel, compute absolute values
        var absoluteSamples = [Float](repeating: 0, count: frameLength)
        vDSP_vabs(channelData[0], 1, &absoluteSamples, 1, vDSP_Length(frameLength))

        // Downsample via averaging
        let samplesPerBin = max(1, frameLength / count)
        let binCount = min(count, frameLength / samplesPerBin)
        guard binCount > 0 else { return [] }

        var result = [Float](repeating: 0, count: binCount)
        let filter = [Float](repeating: 1.0 / Float(samplesPerBin), count: samplesPerBin)
        vDSP_desamp(absoluteSamples, vDSP_Stride(samplesPerBin), filter, &result, vDSP_Length(binCount), vDSP_Length(samplesPerBin))

        // Normalize to 0...1
        var maxVal: Float = 0
        vDSP_maxv(result, 1, &maxVal, vDSP_Length(binCount))
        if maxVal > 0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(binCount))
        }

        return result
    }
}

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

    @StateObject private var waveformLoader = WaveformLoader()

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
                if !waveformLoader.samples.isEmpty {
                    WaveformBarsShape(samples: waveformLoader.samples)
                        .fill(Color.secondary.opacity(0.4))
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
            .onAppear {
                if let url = audioURL {
                    let sampleCount = max(1, Int(geometry.size.width))
                    waveformLoader.load(url: url, count: sampleCount)
                }
            }
            .onDisappear {
                waveformLoader.invalidate()
            }
        }
        .frame(height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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

/// Simple waveform shape that draws vertical bars from normalized 0...1 samples.
private struct WaveformBarsShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        guard !samples.isEmpty else { return Path() }
        var path = Path()
        let barWidth = rect.width / CGFloat(samples.count)
        let midY = rect.midY

        for (index, sample) in samples.enumerated() {
            let amplitude = CGFloat(min(max(sample, 0), 1)) * rect.height * 0.9
            let halfHeight = amplitude / 2
            let x = CGFloat(index) * barWidth
            path.addRect(CGRect(
                x: x,
                y: midY - halfHeight,
                width: max(barWidth - 0.5, 0.5),
                height: max(amplitude, 0.5)
            ))
        }
        return path
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
