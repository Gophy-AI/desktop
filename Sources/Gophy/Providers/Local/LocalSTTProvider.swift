import Foundation

public protocol TranscriptionCapable: TranscriptionEngineProtocol {
    func transcribe(audioArray: [Float], sampleRate: Int, language: String?) async throws -> [TranscriptionSegment]
}

extension TranscriptionEngine: TranscriptionCapable {}

public final class LocalSTTProvider: STTProvider, @unchecked Sendable {
    private let engine: any TranscriptionCapable

    public init(engine: any TranscriptionCapable) {
        self.engine = engine
    }

    public func transcribe(audioData: Data, format: AudioFormat) async throws -> [TranscriptionSegment] {
        guard engine.isLoaded else {
            throw ProviderError.notConfigured
        }

        let audioSamples = convertToFloat32Array(data: audioData, format: format)
        return try await engine.transcribe(audioArray: audioSamples, sampleRate: 16000, language: nil)
    }

    private func convertToFloat32Array(data: Data, format: AudioFormat) -> [Float] {
        switch format {
        case .wav:
            return parseWAVToFloat32(data: data)
        case .mp3, .m4a, .webm:
            // For non-WAV formats, treat as raw 16-bit PCM as fallback
            return parseRawInt16ToFloat32(data: data)
        }
    }

    private func parseWAVToFloat32(data: Data) -> [Float] {
        // WAV header is 44 bytes for standard PCM
        guard data.count > 44 else {
            return []
        }

        let audioData = data.advanced(by: 44)
        return parseRawInt16ToFloat32(data: audioData)
    }

    private func parseRawInt16ToFloat32(data: Data) -> [Float] {
        let sampleCount = data.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let int16Buffer = baseAddress.assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        return samples
    }
}
