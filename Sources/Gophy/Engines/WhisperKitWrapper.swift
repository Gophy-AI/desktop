import Foundation
@_spi(Internal) import WhisperKit

struct WhisperResultWrapper: WhisperResultProtocol {
    let segments: [WhisperSegmentProtocol]

    init(result: TranscriptionResult) {
        self.segments = result.segments.map { segment in
            WhisperSegmentWrapper(
                text: segment.text,
                start: segment.start,
                end: segment.end
            )
        }
    }
}

struct WhisperSegmentWrapper: WhisperSegmentProtocol {
    let text: String
    let start: Float
    let end: Float
}

public final class WhisperKitWrapper: WhisperKitProtocol, @unchecked Sendable {
    private let whisperKit: WhisperKit

    public init(modelFolder: String) async throws {
        self.whisperKit = try await WhisperKit(modelFolder: modelFolder)
    }

    public func transcribe(audioArray: [Float], language: String? = nil) async throws -> [WhisperResultProtocol] {
        var options = DecodingOptions()
        if let language = language {
            options.language = language
        }
        let results = try await whisperKit.transcribe(audioArray: audioArray, decodeOptions: options)
        return results.map { WhisperResultWrapper(result: $0) }
    }
}
