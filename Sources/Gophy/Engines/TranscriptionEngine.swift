import Foundation
import WhisperKit

public typealias WhisperKitLoader = @Sendable (String) async throws -> any WhisperKitProtocol

public final class TranscriptionEngine: @unchecked Sendable {
    private var whisperKit: (any WhisperKitProtocol)?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol
    private let whisperKitLoader: WhisperKitLoader

    public init(
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared,
        whisperKitLoader: @escaping WhisperKitLoader = { modelPath in
            try await WhisperKitWrapper(modelFolder: modelPath)
        }
    ) {
        self.modelRegistry = modelRegistry
        self.whisperKitLoader = whisperKitLoader
    }

    public func load() async throws {
        guard let sttModel = modelRegistry.availableModels().first(where: { $0.type == .stt }) else {
            throw TranscriptionError.noModelAvailable
        }
        let modelPath = modelRegistry.downloadPath(for: sttModel).path

        whisperKit = try await whisperKitLoader(modelPath)
        isLoaded = true
    }

    public func transcribe(audioArray: [Float], sampleRate: Int = 16000) async throws -> [TranscriptionSegment] {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let results = try await whisperKit.transcribe(audioArray: audioArray)

        return results.flatMap { result in
            result.segments.map { segment in
                TranscriptionSegment(
                    text: segment.text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                )
            }
        }
    }

    public func unload() {
        whisperKit = nil
        isLoaded = false
    }
}

public enum TranscriptionError: Error, Sendable {
    case modelNotLoaded
    case invalidAudioFormat
    case noModelAvailable
}
