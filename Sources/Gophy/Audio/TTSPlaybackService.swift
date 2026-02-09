@preconcurrency import AVFoundation
import Foundation
import os.log

private let ttsPlaybackLogger = Logger(subsystem: "com.gophy.app", category: "TTSPlayback")

/// Errors for TTSPlaybackService
public enum TTSPlaybackError: Error, LocalizedError, Sendable {
    case engineNotAvailable
    case alreadyPlaying
    case synthesizeFailed(String)
    case audioEngineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .engineNotAvailable:
            return "TTS engine not available"
        case .alreadyPlaying:
            return "Already playing audio"
        case .synthesizeFailed(let reason):
            return "Speech synthesis failed: \(reason)"
        case .audioEngineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        }
    }
}

/// Manages TTS audio playback using AVAudioEngine.
///
/// Must be @MainActor (not an actor) because AVAudioEngine is not Sendable
/// and must be used from the main thread. This matches the pattern used by
/// mlx-audio-swift's AudioPlayerManager.
@MainActor
@Observable
public final class TTSPlaybackService {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let ttsEngine: any TTSEngineProtocol
    private var playbackTask: Task<Void, Never>?

    /// Sample rate for PCM audio format. Defaults to 22050 Hz (Soprano model).
    /// Different TTS models use different rates: Soprano 22050, Orpheus 24000, etc.
    public var sampleRate: Double = 22050.0

    public private(set) var isPlaying: Bool = false
    public private(set) var isLoading: Bool = false

    /// The text currently being spoken, if any.
    public private(set) var currentText: String?

    public init(ttsEngine: any TTSEngineProtocol) {
        self.ttsEngine = ttsEngine
    }

    /// Synthesize text and play it through the system default audio output.
    public func play(text: String, voice: String? = nil) {
        guard !isPlaying else {
            ttsPlaybackLogger.warning("play() called while already playing, stopping first")
            stop()
            return
        }

        currentText = text
        isLoading = true

        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performPlayback(text: text, voice: voice)
            } catch {
                ttsPlaybackLogger.error("Playback failed: \(error.localizedDescription, privacy: .public)")
                self.resetState()
            }
        }
    }

    /// Stop any active playback.
    public func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        teardownAudioEngine()
        resetState()
        ttsPlaybackLogger.info("Playback stopped")
    }

    // MARK: - Private

    private func performPlayback(text: String, voice: String?) async throws {
        guard ttsEngine.isLoaded else {
            ttsPlaybackLogger.error("TTS engine not loaded")
            resetState()
            throw TTSPlaybackError.engineNotAvailable
        }

        ttsPlaybackLogger.info("Synthesizing text of length \(text.count, privacy: .public)")

        let samples: [Float]
        do {
            samples = try await ttsEngine.synthesize(text: text, voice: voice)
        } catch {
            resetState()
            throw TTSPlaybackError.synthesizeFailed(error.localizedDescription)
        }

        guard !Task.isCancelled else {
            resetState()
            return
        }

        guard !samples.isEmpty else {
            ttsPlaybackLogger.warning("Synthesize returned empty samples")
            resetState()
            return
        }

        ttsPlaybackLogger.info("Synthesized \(samples.count, privacy: .public) samples, playing at \(self.sampleRate, privacy: .public) Hz")

        isLoading = false
        isPlaying = true

        try playAudioSamples(samples)
    }

    private func playAudioSamples(_ samples: [Float]) throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TTSPlaybackError.audioEngineStartFailed("Failed to create PCM format")
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TTSPlaybackError.audioEngineStartFailed("Failed to create audio buffer")
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else {
            throw TTSPlaybackError.audioEngineStartFailed("Failed to access buffer channel data")
        }

        samples.withUnsafeBufferPointer { ptr in
            channelData[0].update(from: ptr.baseAddress!, count: samples.count)
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            throw TTSPlaybackError.audioEngineStartFailed(error.localizedDescription)
        }

        self.audioEngine = engine
        self.playerNode = player

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackCompletion()
            }
        }

        player.play()

        ttsPlaybackLogger.info("Audio playback started")
    }

    private func handlePlaybackCompletion() {
        guard isPlaying else { return }
        teardownAudioEngine()
        resetState()
        ttsPlaybackLogger.info("Playback completed naturally")
    }

    private func teardownAudioEngine() {
        playerNode?.stop()
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        if let player = playerNode {
            audioEngine?.detach(player)
        }
        audioEngine = nil
        playerNode = nil
    }

    private func resetState() {
        isPlaying = false
        isLoading = false
        currentText = nil
    }
}
