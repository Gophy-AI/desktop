import Foundation

public enum AudioFormat: String, Sendable {
    case wav
    case mp3
    case m4a
    case webm
}

public protocol TextGenerationProvider: Sendable {
    func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>
}

public protocol EmbeddingProvider: Sendable {
    func embed(text: String) async throws -> [Float]
    func embedBatch(texts: [String]) async throws -> [[Float]]
    var dimensions: Int { get }
}

public protocol STTProvider: Sendable {
    func transcribe(audioData: Data, format: AudioFormat) async throws -> [TranscriptionSegment]
}

public protocol VisionProvider: Sendable {
    func extractText(from imageData: Data, prompt: String) async throws -> String
    func analyzeImage(imageData: Data, prompt: String) -> AsyncThrowingStream<String, Error>
}

public protocol TTSProvider: Sendable {
    func synthesize(text: String, voice: String?) async throws -> Data
    func synthesizeStream(text: String, voice: String?) -> AsyncThrowingStream<Data, Error>
    var sampleRate: Int { get }
}
