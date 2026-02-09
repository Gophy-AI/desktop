import Foundation
import CoreAudio
import AVFoundation

/// Protocol for system audio capture to enable testing
public protocol SystemAudioCaptureProtocol: Sendable {
    /// Start capturing system audio
    /// - Returns: AsyncStream of AudioChunk instances (16kHz mono float32)
    nonisolated func start() -> AsyncStream<AudioChunk>

    /// Stop capturing system audio and clean up resources
    func stop() async
}

/// System audio capture service using CoreAudio ProcessTap (macOS 14.4+)
///
/// Captures system audio output without Screen Recording permission using the
/// ProcessTap API introduced in macOS 14.4. Creates an aggregate audio device
/// with a tap on system audio, converts to 16kHz mono float32, and emits via
/// AsyncStream.
///
/// Reference: AudioCap (github.com/insidegui/AudioCap)
@available(macOS 14.4, *)
public actor SystemAudioCaptureService: SystemAudioCaptureProtocol {
    
    private var tapID: AudioDeviceID?
    private var aggregateDeviceID: AudioDeviceID?
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var startTime: TimeInterval = 0
    private var audioConverter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    private let targetSampleRate: Double = 16000
    private let targetChannelCount: UInt32 = 1
    
    public init() {}

    nonisolated public func start() -> AsyncStream<AudioChunk> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.setupCapture(continuation: continuation)
            }
        }
    }
    
    public func stop() async {
        guard isRunning else { return }
        
        isRunning = false
        
        // Remove IO proc
        if let ioProcID = ioProcID, let aggregateDeviceID = aggregateDeviceID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        
        // Destroy aggregate device
        if let aggregateDeviceID = aggregateDeviceID {
            destroyAggregateDevice(aggregateDeviceID)
            self.aggregateDeviceID = nil
        }
        
        // Destroy process tap
        if let tapID = tapID {
            destroyProcessTap(tapID)
            self.tapID = nil
        }
        
        audioConverter = nil
        sourceFormat = nil
        continuation?.finish()
        continuation = nil
    }
    
    // MARK: - Private Setup
    
    private func setupCapture(continuation: AsyncStream<AudioChunk>.Continuation) async {
        self.continuation = continuation
        self.isRunning = true
        self.startTime = CACurrentMediaTime()

        do {
            // Create ProcessTap for system audio
            let tap = try createProcessTap()
            self.tapID = tap

            // Create aggregate device with the tap
            let aggregateDevice = try createAggregateDevice(with: tap)
            self.aggregateDeviceID = aggregateDevice

            // Detect source sample rate from the aggregate device
            var nominalSampleRate: Float64 = 48000.0
            var srSize = UInt32(MemoryLayout<Float64>.size)
            var srAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(aggregateDevice, &srAddress, 0, nil, &srSize, &nominalSampleRate)

            // Create input format (interleaved stereo float32 at source rate)
            guard let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: nominalSampleRate,
                channels: 2,
                interleaved: true
            ) else {
                throw SystemAudioCaptureError.formatCreationFailed
            }
            self.sourceFormat = inputFormat

            // Create output format (non-interleaved mono float32 at 16kHz)
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw SystemAudioCaptureError.formatCreationFailed
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw SystemAudioCaptureError.converterCreationFailed
            }
            self.audioConverter = converter

            // Set up IO proc for audio callbacks
            try setupIOProc(for: aggregateDevice)

            // Start the device
            try startDevice(aggregateDevice)

        } catch {
            continuation.finish()
            isRunning = false
        }
    }
    
    // MARK: - ProcessTap Creation
    
    private func createProcessTap() throws -> AudioDeviceID {
        var tapDescription = CATapDescription()
        
        // Configure tap for system audio output
        // UUID for system-wide tap (null UUID means all processes)
        tapDescription.uuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        
        // Tap format: stereo 48kHz float32 (we'll convert to 16kHz mono later)
        tapDescription.tapMode = kCATapModeListenOnly
        tapDescription.stereoMixdown = true
        
        var tapID: AudioDeviceID = 0
        var tapIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyCreateProcessTap),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = withUnsafeMutablePointer(to: &tapDescription) { tapDescPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CATapDescription>.size),
                tapDescPtr,
                &tapIDSize,
                &tapID
            )
        }
        
        guard status == noErr else {
            throw SystemAudioCaptureError.tapCreationFailed(status)
        }
        
        return tapID
    }
    
    // MARK: - Aggregate Device Creation
    
    private func createAggregateDevice(with tapID: AudioDeviceID) throws -> AudioDeviceID {
        let aggregateDeviceDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Gophy System Audio Tap",
            kAudioAggregateDeviceUIDKey: "com.gophy.system-audio-tap",
            kAudioAggregateDeviceSubDeviceListKey: [tapID],
            kAudioAggregateDeviceMainSubDeviceKey: tapID,
            kAudioAggregateDeviceIsPrivateKey: 1
        ]
        
        var aggregateDeviceID: AudioDeviceID = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioPlugInCreateAggregateDevice),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var outDataSize: UInt32 = 0
        let status = withUnsafePointer(to: aggregateDeviceDict as CFDictionary) { dictPtr in
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &outDataSize
            )
            
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CFDictionary>.size),
                dictPtr,
                &outDataSize,
                &aggregateDeviceID
            )
        }
        
        guard status == noErr else {
            throw SystemAudioCaptureError.aggregateDeviceCreationFailed(status)
        }
        
        return aggregateDeviceID
    }
    
    // MARK: - IO Proc Setup
    
    private func setupIOProc(for deviceID: AudioDeviceID) throws {
        var ioProcID: AudioDeviceIOProcID?

        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            deviceID,
            nil
        ) { [weak self] (
            inNow: UnsafePointer<AudioTimeStamp>,
            inInputData: UnsafePointer<AudioBufferList>,
            inInputTime: UnsafePointer<AudioTimeStamp>,
            outOutputData: UnsafeMutablePointer<AudioBufferList>,
            inOutputTime: UnsafePointer<AudioTimeStamp>
        ) in
            guard let self = self else { return }

            // Copy buffer data immediately before Task boundary
            let bufferCount = Int(inInputData.pointee.mNumberBuffers)
            guard bufferCount > 0 else { return }

            let buffer = inInputData.pointee.mBuffers
            guard let data = buffer.mData else { return }

            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            let samplesArray = Array(UnsafeBufferPointer<Float>(start: samples, count: sampleCount))
            let channelCount = Int(buffer.mNumberChannels)
            let captureTime = CACurrentMediaTime()

            // Now process with copied data in async context
            Task {
                await self.processAudioSamples(samplesArray, channelCount: channelCount, captureTime: captureTime)
            }
        }

        guard status == noErr, let procID = ioProcID else {
            throw SystemAudioCaptureError.ioProcCreationFailed(status)
        }

        self.ioProcID = procID
    }

    private func processAudioSamples(_ samplesArray: [Float], channelCount: Int, captureTime: TimeInterval) async {
        guard let converter = audioConverter else { return }

        // Build an AVAudioPCMBuffer from the raw interleaved samples
        let frameCount = AVAudioFrameCount(samplesArray.count / channelCount)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.inputFormat,
            frameCapacity: frameCount
        ) else { return }
        inputBuffer.frameLength = frameCount

        // Copy interleaved samples into the buffer
        if let bufferData = inputBuffer.floatChannelData {
            samplesArray.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                bufferData[0].update(from: base, count: samplesArray.count)
            }
        }

        // Calculate output frame count
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil,
              let outData = outputBuffer.floatChannelData else { return }

        let count = Int(outputBuffer.frameLength)
        let convertedSamples = Array(UnsafeBufferPointer(start: outData[0], count: count))

        // Create chunk and emit
        let timestamp = captureTime - startTime
        let chunk = AudioChunk(
            samples: convertedSamples,
            timestamp: timestamp,
            source: .systemAudio
        )

        continuation?.yield(chunk)
    }

    // MARK: - Device Control

    private func startDevice(_ deviceID: AudioDeviceID) throws {
        guard let ioProcID = ioProcID else {
            throw SystemAudioCaptureError.noProcID
        }

        let status = AudioDeviceStart(deviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioCaptureError.deviceStartFailed(status)
        }
    }
    
    // MARK: - Cleanup
    
    private func destroyProcessTap(_ tapID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDestroyProcessTap),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapIDCopy = tapID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            size,
            &tapIDCopy
        )
    }
    
    private func destroyAggregateDevice(_ deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioPlugInDestroyAggregateDevice),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceIDCopy = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            size,
            &deviceIDCopy
        )
    }
}

// MARK: - CATapDescription

/// CoreAudio Tap Description structure (macOS 14.4+)
struct CATapDescription {
    var uuid: UUID = UUID()
    var tapMode: UInt32 = 0
    var stereoMixdown: Bool = false
    var reserved: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
}

// MARK: - Constants

let kCATapModeListenOnly: UInt32 = 0

let kAudioHardwarePropertyCreateProcessTap: UInt32 = 0x70746170  // 'ptap'
let kAudioHardwarePropertyDestroyProcessTap: UInt32 = 0x70746170 // 'ptap'

// MARK: - Errors

public enum SystemAudioCaptureError: Error, Sendable {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case noProcID
    case unsupportedMacOSVersion
    case formatCreationFailed
    case converterCreationFailed
}
