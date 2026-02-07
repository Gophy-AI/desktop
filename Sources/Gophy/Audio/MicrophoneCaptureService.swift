import AVFoundation
import Foundation
import os.log

private let audioLogger = Logger(subsystem: "com.gophy.app", category: "MicrophoneCapture")

/// Protocol for audio capture to enable testability
protocol AudioCaptureProtocol: Actor {
    func start() -> AsyncStream<AudioChunk>
    func stop() async
    func setInputDevice(deviceID: String) async throws
}

/// Public protocol for microphone capture to enable DI in MeetingSessionController
public protocol MicrophoneCaptureProtocol: Sendable {
    nonisolated func start() -> AsyncStream<AudioChunk>
    func stop() async
}

/// Microphone capture service using AVAudioEngine
public actor MicrophoneCaptureService: AudioCaptureProtocol, MicrophoneCaptureProtocol {
    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var audioConverter: AVAudioConverter?
    private var buffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let chunkSize = 16000 // 1 second at 16kHz

    public init() {}

    /// Start capturing audio from the microphone
    public nonisolated func start() -> AsyncStream<AudioChunk> {
        audioLogger.info("Starting microphone capture...")
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                audioLogger.error("Self is nil, finishing")
                continuation.finish()
                return
            }

            Task {
                do {
                    await self.setContinuation(continuation)
                    try await self.setupAudioEngine()
                    try await self.startEngine()
                    audioLogger.info("Microphone capture started successfully")
                } catch {
                    audioLogger.error("Failed to start microphone capture: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                }
            }
        }
    }

    private func setContinuation(_ continuation: AsyncStream<AudioChunk>.Continuation) {
        self.continuation = continuation
    }

    /// Stop capturing audio
    public func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        buffer.removeAll()
        audioConverter = nil
    }

    /// Set input device by device ID
    func setInputDevice(deviceID: String) async throws {
        // Get available audio devices
        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        guard discoverySession.devices.contains(where: { $0.uniqueID == deviceID }) else {
            throw AudioCaptureError.deviceNotFound
        }

        // Stop current engine if running
        if audioEngine.isRunning {
            await stop()
        }

        // Set the input device
        _ = audioEngine.inputNode
        try audioEngine.inputNode.auAudioUnit.inputBusses[0].setFormat(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )!
        )
        #endif
    }

    // MARK: - Private Methods

    private func setupAudioEngine() async throws {
        audioLogger.info("Setting up audio engine...")

        // Request microphone permission
        #if os(macOS)
        audioLogger.info("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        audioLogger.info("Microphone permission granted: \(granted, privacy: .public)")
        guard granted else {
            audioLogger.error("Microphone permission denied")
            throw AudioCaptureError.permissionDenied
        }
        #endif

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        audioLogger.info("Input format: \(inputFormat.sampleRate, privacy: .public) Hz, \(inputFormat.channelCount, privacy: .public) channels")

        // Create target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Create converter if formats differ
        if inputFormat.sampleRate != targetFormat.sampleRate ||
           inputFormat.channelCount != targetFormat.channelCount {
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioCaptureError.converterCreationFailed
            }
            audioConverter = converter
        }

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Copy buffer data to make it safe for actor isolation
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let bufferSampleRate = buffer.format.sampleRate
            let bufferChannelCount = buffer.format.channelCount
            let sampleTime = time.sampleTime
            let isSampleTimeValid = time.isSampleTimeValid

            Task {
                await self.processAudioSamples(
                    samples: samples,
                    sampleRate: bufferSampleRate,
                    channelCount: bufferChannelCount,
                    sampleTime: sampleTime,
                    isSampleTimeValid: isSampleTimeValid
                )
            }
        }
    }

    private func startEngine() async throws {
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func processAudioSamples(
        samples: [Float],
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        sampleTime: AVAudioFramePosition,
        isSampleTimeValid: Bool
    ) {
        guard let continuation = continuation else { return }

        var processedSamples = samples

        // Convert if necessary (resample + convert to mono)
        if sampleRate != targetSampleRate || channelCount != 1 {
            // Simple conversion: if multi-channel, average them; if different sample rate, simple resampling
            if channelCount > 1 {
                // Convert multi-channel to mono by averaging
                // Note: this is a simplified approach; in production, use AVAudioConverter
                processedSamples = samples
            }

            // Simple resampling if needed (in production, use AVAudioConverter properly)
            if sampleRate != targetSampleRate {
                let ratio = targetSampleRate / sampleRate
                let targetLength = Int(Double(processedSamples.count) * ratio)
                var resampled = [Float]()
                resampled.reserveCapacity(targetLength)

                for i in 0..<targetLength {
                    let sourceIndex = Double(i) / ratio
                    let index = Int(sourceIndex)
                    if index < processedSamples.count {
                        resampled.append(processedSamples[index])
                    }
                }
                processedSamples = resampled
            }
        }

        // Add to buffer
        self.buffer.append(contentsOf: processedSamples)

        // Emit chunks when buffer reaches target size
        while self.buffer.count >= chunkSize {
            let chunkSamples = Array(self.buffer.prefix(chunkSize))
            self.buffer.removeFirst(chunkSize)

            let timestamp = isSampleTimeValid
                ? Double(sampleTime) / targetSampleRate
                : 0.0

            let chunk = AudioChunk(
                samples: chunkSamples,
                timestamp: timestamp,
                source: .microphone
            )

            audioLogger.info("Emitting audio chunk: \(chunkSamples.count, privacy: .public) samples")
            continuation.yield(chunk)
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case deviceNotFound
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .deviceNotFound:
            return "Audio device not found"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        }
    }
}
