import Foundation

public final class LocalTTSProvider: TTSProvider, @unchecked Sendable {
    private let engine: any TTSEngineProtocol
    public let sampleRate: Int

    public init(engine: any TTSEngineProtocol, sampleRate: Int = 22050) {
        self.engine = engine
        self.sampleRate = sampleRate
    }

    public func synthesize(text: String, voice: String?) async throws -> Data {
        let samples = try await engine.synthesize(text: text, voice: voice)
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    public func synthesizeStream(text: String, voice: String?) -> AsyncThrowingStream<Data, Error> {
        let engineStream = engine.synthesizeStream(text: text, voice: voice)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in engineStream {
                        let pcmData = floatsToPCMInt16(chunk)
                        continuation.yield(pcmData)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - WAV Encoding

    private func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let pcmData = floatsToPCMInt16(samples)
        return buildWAVHeader(dataSize: pcmData.count, sampleRate: sampleRate) + pcmData
    }

    private func floatsToPCMInt16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: &int16Sample) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func buildWAVHeader(dataSize: Int, sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let chunkSize = UInt32(36 + dataSize)

        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        appendUInt32(&header, chunkSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        appendUInt32(&header, 16) // Sub-chunk size for PCM
        appendUInt16(&header, 1)  // Audio format: PCM
        appendUInt16(&header, numChannels)
        appendUInt32(&header, UInt32(sampleRate))
        appendUInt32(&header, byteRate)
        appendUInt16(&header, blockAlign)
        appendUInt16(&header, bitsPerSample)

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        appendUInt32(&header, UInt32(dataSize))

        return header
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
