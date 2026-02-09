import Foundation

public enum ModelType: String, Codable, Sendable {
    case stt
    case textGen
    case ocr
    case embedding
    case tts
}

public enum ModelSource: String, Codable, Sendable {
    case curated
    case llmRegistry
    case vlmRegistry
    case embeddersRegistry
    case audioRegistry
}

public struct ModelDefinition: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: ModelType
    public let huggingFaceID: String
    public let approximateSizeGB: Double?
    public let memoryUsageGB: Double?
    public let source: ModelSource

    public init(
        id: String,
        name: String,
        type: ModelType,
        huggingFaceID: String,
        approximateSizeGB: Double?,
        memoryUsageGB: Double?,
        source: ModelSource = .curated
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.huggingFaceID = huggingFaceID
        self.approximateSizeGB = approximateSizeGB
        self.memoryUsageGB = memoryUsageGB
        self.source = source
    }
}
