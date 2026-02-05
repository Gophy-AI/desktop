import Foundation

public protocol WhisperKitProtocol: Sendable {
    func transcribe(audioArray: [Float]) async throws -> [WhisperResultProtocol]
}

public protocol WhisperResultProtocol: Sendable {
    var segments: [WhisperSegmentProtocol] { get }
}

public protocol WhisperSegmentProtocol: Sendable {
    var text: String { get }
    var start: Float { get }
    var end: Float { get }
}
