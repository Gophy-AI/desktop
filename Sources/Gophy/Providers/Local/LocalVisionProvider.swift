import Foundation
@preconcurrency import CoreImage

public protocol VisionCapable: OCREngineActorProtocol {
    func extractText(from image: CIImage) async throws -> String
}

extension OCREngine: VisionCapable {}

public final class LocalVisionProvider: VisionProvider, @unchecked Sendable {
    private let engine: any VisionCapable

    public init(engine: any VisionCapable) {
        self.engine = engine
    }

    public func extractText(from imageData: Data, prompt: String) async throws -> String {
        let isLoaded = await engine.isLoaded
        guard isLoaded else {
            throw ProviderError.notConfigured
        }

        guard let ciImage = CIImage(data: imageData) else {
            throw ProviderError.streamingError("Failed to create image from data")
        }

        return try await engine.extractText(from: ciImage)
    }

    public func analyzeImage(imageData: Data, prompt: String) -> AsyncThrowingStream<String, Error> {
        let engine = self.engine
        return AsyncThrowingStream { continuation in
            Task {
                let isLoaded = await engine.isLoaded
                guard isLoaded else {
                    continuation.finish(throwing: ProviderError.notConfigured)
                    return
                }

                guard let ciImage = CIImage(data: imageData) else {
                    continuation.finish(throwing: ProviderError.streamingError("Failed to create image from data"))
                    return
                }

                do {
                    let result = try await engine.extractText(from: ciImage)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
