import AVFoundation
import Foundation
import os.log

private let playbackLogger = Logger(subsystem: "com.gophy.app", category: "RecordingPlayback")

/// Errors for RecordingPlaybackService
public enum RecordingPlaybackError: Error, LocalizedError, Sendable {
    case noFileLoaded
    case alreadyPlaying
    case notPlaying
    case engineStartFailed(String)
    case seekOutOfRange

    public var errorDescription: String? {
        switch self {
        case .noFileLoaded:
            return "No audio file loaded"
        case .alreadyPlaying:
            return "Playback is already in progress"
        case .notPlaying:
            return "Playback is not active"
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .seekOutOfRange:
            return "Seek position is out of range"
        }
    }
}

/// Protocol for recording playback to enable testability
public protocol RecordingPlaybackProtocol: Actor {
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var speed: Float { get }

    func loadFile(url: URL) async throws
    func play() async throws -> AsyncStream<AudioChunk>
    func pause() async
    func resume() async throws
    func stop() async
    func seek(to time: TimeInterval) async throws
    func setSpeed(_ rate: Float) async
}

/// Manages audio file playback with real-time sample extraction for the transcription pipeline.
///
/// AVAudioEngine graph:
///   AVAudioPlayerNode -> AVAudioUnitTimePitch -> mainMixerNode -> outputNode
///   Tap installed on mainMixerNode to extract audio samples.
///
/// Emits AsyncStream<AudioChunk> for downstream consumption by the transcription pipeline.
public actor RecordingPlaybackService: RecordingPlaybackProtocol {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var audioFile: AVAudioFile?
    private var fileInfo: AudioFileInfo?
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    private var buffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let chunkSize = 16000 // 1 second at 16kHz
    private var playbackStartFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var tapInstalled = false

    public private(set) var state: PlaybackState = .idle
    public private(set) var speed: Float = 1.0

    public var currentTime: TimeInterval {
        guard let file = audioFile else { return 0 }
        let sampleRate = file.processingFormat.sampleRate

        if state == .playing, let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let framePlayed = playerTime.sampleTime
            let totalFrame = playbackStartFrame + framePlayed
            return Double(totalFrame) / sampleRate
        }

        if state == .paused {
            return Double(pausedFrame) / sampleRate
        }

        return Double(playbackStartFrame) / sampleRate
    }

    public var duration: TimeInterval {
        guard let info = fileInfo else { return 0 }
        return info.duration
    }

    public init() {}

    /// Load an audio file for playback
    public func loadFile(url: URL) async throws {
        let importer = AudioFileImporter()
        let info = try await importer.importFile(url: url)

        let file = try AVAudioFile(forReading: url)
        self.audioFile = file
        self.fileInfo = info
        self.playbackStartFrame = 0
        self.pausedFrame = 0
        self.state = .loaded

        playbackLogger.info("Loaded file: \(url.lastPathComponent, privacy: .public), duration: \(String(format: "%.1f", info.duration), privacy: .public)s")
    }

    /// Start playback and return a stream of audio chunks for the transcription pipeline
    public func play() async throws -> AsyncStream<AudioChunk> {
        guard let file = audioFile else {
            throw RecordingPlaybackError.noFileLoaded
        }

        guard state == .loaded || state == .stopped else {
            throw RecordingPlaybackError.alreadyPlaying
        }

        playbackStartFrame = 0
        buffer.removeAll()

        return try startPlaybackEngine(file: file, fromFrame: 0)
    }

    /// Pause playback
    public func pause() {
        guard state == .playing else { return }

        // Capture current position before pausing
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            pausedFrame = playbackStartFrame + playerTime.sampleTime
        }

        // Fully stop the engine to cleanly release the tap.
        // Resume will restart from pausedFrame.
        stopEngine()
        state = .paused

        playbackLogger.info("Playback paused at \(String(format: "%.1f", self.currentTime), privacy: .public)s")
    }

    /// Resume playback after pause
    public func resume() async throws {
        guard state == .paused else {
            throw RecordingPlaybackError.notPlaying
        }

        guard let file = audioFile else {
            throw RecordingPlaybackError.noFileLoaded
        }

        // Restart engine and schedule from paused position
        playbackStartFrame = pausedFrame

        stopEngine()
        _ = try startPlaybackEngine(file: file, fromFrame: playbackStartFrame)
    }

    /// Stop playback completely
    public func stop() {
        stopEngine()
        continuation?.finish()
        continuation = nil
        buffer.removeAll()
        playbackStartFrame = 0
        pausedFrame = 0
        state = .stopped

        playbackLogger.info("Playback stopped")
    }

    /// Seek to a specific time position
    public func seek(to time: TimeInterval) async throws {
        guard let file = audioFile, let info = fileInfo else {
            throw RecordingPlaybackError.noFileLoaded
        }

        guard time >= 0 && time <= info.duration else {
            throw RecordingPlaybackError.seekOutOfRange
        }

        let targetFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
        let wasPlaying = state == .playing

        stopEngine()
        buffer.removeAll()
        playbackStartFrame = targetFrame
        pausedFrame = targetFrame

        if wasPlaying {
            _ = try startPlaybackEngine(file: file, fromFrame: targetFrame)
        } else {
            state = .loaded
        }

        playbackLogger.info("Seeked to \(String(format: "%.1f", time), privacy: .public)s")
    }

    /// Set playback speed (0.25x to 4.0x)
    public func setSpeed(_ rate: Float) {
        let clampedRate = min(max(rate, 0.25), 4.0)
        speed = clampedRate
        timePitch.rate = clampedRate

        playbackLogger.info("Speed set to \(String(format: "%.2f", clampedRate), privacy: .public)x")
    }

    // MARK: - Private

    @discardableResult
    private func startPlaybackEngine(file: AVAudioFile, fromFrame: AVAudioFramePosition) throws -> AsyncStream<AudioChunk> {
        let fileFormat = file.processingFormat
        let totalFrames = file.length
        let remainingFrames = AVAudioFrameCount(totalFrames - fromFrame)

        guard remainingFrames > 0 else {
            state = .stopped
            return AsyncStream { $0.finish() }
        }

        // Attach nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)

        // Connect: playerNode -> timePitch -> mainMixer -> output
        audioEngine.connect(playerNode, to: timePitch, format: fileFormat)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: fileFormat)

        // Set current speed
        timePitch.rate = speed

        // Install tap on mixer node before creating the stream
        installTap()

        // Create the AsyncStream and store the continuation synchronously
        var streamContinuation: AsyncStream<AudioChunk>.Continuation!
        let stream = AsyncStream<AudioChunk> { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation

        // Schedule file segment
        file.framePosition = fromFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: fromFrame,
            frameCount: remainingFrames,
            at: nil
        )

        // Start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw RecordingPlaybackError.engineStartFailed(error.localizedDescription)
        }

        playerNode.play()
        state = .playing

        playbackLogger.info("Playback started from frame \(fromFrame, privacy: .public)")

        return stream
    }

    private func removeTapIfNeeded() {
        if tapInstalled {
            audioEngine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func installTap() {
        removeTapIfNeeded()
        let mixerNode = audioEngine.mainMixerNode
        let mixerFormat = mixerNode.outputFormat(forBus: 0)

        // Install tap on mixer to capture audio samples
        let bufferSize: AVAudioFrameCount = 4096
        tapInstalled = true
        mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: mixerFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            let sampleRate = buffer.format.sampleRate

            // Copy samples to make safe for actor isolation
            var samples: [Float]
            if channelCount > 1 {
                // Convert to mono by averaging channels
                samples = [Float](repeating: 0, count: frameLength)
                for frame in 0..<frameLength {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += channelData[ch][frame]
                    }
                    samples[frame] = sum / Float(channelCount)
                }
            } else {
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }

            Task {
                await self.processPlaybackSamples(
                    samples: samples,
                    sampleRate: sampleRate
                )
            }
        }
    }

    private func processPlaybackSamples(samples: [Float], sampleRate: Double) {
        guard let continuation = continuation, state == .playing else { return }

        var processedSamples = samples

        // Resample to 16kHz if needed
        if sampleRate != targetSampleRate {
            let ratio = targetSampleRate / sampleRate
            let targetLength = Int(Double(processedSamples.count) * ratio)
            var resampled = [Float]()
            resampled.reserveCapacity(targetLength)

            for i in 0..<targetLength {
                let sourceIndex = Double(i) / ratio
                let index = Int(sourceIndex)
                let fraction = Float(sourceIndex - Double(index))
                if index + 1 < processedSamples.count {
                    resampled.append(processedSamples[index] * (1 - fraction) + processedSamples[index + 1] * fraction)
                } else if index < processedSamples.count {
                    resampled.append(processedSamples[index])
                }
            }
            processedSamples = resampled
        }

        // Add to buffer
        buffer.append(contentsOf: processedSamples)

        // Emit chunks when buffer reaches target size
        while buffer.count >= chunkSize {
            let chunkSamples = Array(buffer.prefix(chunkSize))
            buffer.removeFirst(chunkSize)

            let timestamp = currentTime

            let chunk = AudioChunk(
                samples: chunkSamples,
                timestamp: timestamp,
                source: .systemAudio
            )

            continuation.yield(chunk)
        }
    }

    private func handlePlaybackCompletion() {
        guard state == .playing else { return }

        // Flush remaining buffer
        if !buffer.isEmpty, let continuation = continuation {
            let chunk = AudioChunk(
                samples: buffer,
                timestamp: currentTime,
                source: .systemAudio
            )
            continuation.yield(chunk)
            buffer.removeAll()
        }

        continuation?.finish()
        continuation = nil
        stopEngine()
        state = .stopped

        playbackLogger.info("Playback completed")
    }

    private func stopEngine() {
        removeTapIfNeeded()
        if audioEngine.isRunning {
            playerNode.stop()
            audioEngine.stop()
        }
        audioEngine.detach(playerNode)
        audioEngine.detach(timePitch)
    }
}
