import Foundation

public enum ProviderCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case textGeneration
    case embedding
    case speechToText
    case vision
    case textToSpeech
}

public struct CloudModelDefinition: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let capability: ProviderCapability
    public let contextWindow: Int?
    public let inputPricePer1MTokens: Double?
    public let outputPricePer1MTokens: Double?

    public init(
        id: String,
        name: String,
        capability: ProviderCapability,
        contextWindow: Int? = nil,
        inputPricePer1MTokens: Double? = nil,
        outputPricePer1MTokens: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.capability = capability
        self.contextWindow = contextWindow
        self.inputPricePer1MTokens = inputPricePer1MTokens
        self.outputPricePer1MTokens = outputPricePer1MTokens
    }
}

public struct ProviderConfiguration: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let baseURL: URL
    public let isOpenAICompatible: Bool
    public let supportedCapabilities: Set<ProviderCapability>
    public let availableModels: [CloudModelDefinition]

    public init(
        id: String,
        name: String,
        baseURL: URL,
        isOpenAICompatible: Bool,
        supportedCapabilities: Set<ProviderCapability>,
        availableModels: [CloudModelDefinition]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.isOpenAICompatible = isOpenAICompatible
        self.supportedCapabilities = supportedCapabilities
        self.availableModels = availableModels
    }
}
