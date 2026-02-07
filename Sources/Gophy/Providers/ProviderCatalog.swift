import Foundation

public enum ProviderCatalog {
    public static let all: [ProviderConfiguration] = [
        openai, googleGemini, anthropic, groq, togetherAI,
        mistralAI, deepseek, fireworksAI, openRouter
    ]

    public static func provider(id: String) -> ProviderConfiguration? {
        all.first { $0.id == id }
    }

    // MARK: - OpenAI

    public static let openai = ProviderConfiguration(
        id: "openai",
        name: "OpenAI",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .embedding, .speechToText, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "gpt-4o",
                name: "GPT-4o",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 2.50,
                outputPricePer1MTokens: 10.00
            ),
            CloudModelDefinition(
                id: "gpt-4o-mini",
                name: "GPT-4o Mini",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 0.15,
                outputPricePer1MTokens: 0.60
            ),
            CloudModelDefinition(
                id: "gpt-4o",
                name: "GPT-4o (Vision)",
                capability: .vision,
                contextWindow: 128_000,
                inputPricePer1MTokens: 2.50,
                outputPricePer1MTokens: 10.00
            ),
            CloudModelDefinition(
                id: "text-embedding-3-small",
                name: "Text Embedding 3 Small",
                capability: .embedding,
                inputPricePer1MTokens: 0.02
            ),
            CloudModelDefinition(
                id: "text-embedding-3-large",
                name: "Text Embedding 3 Large",
                capability: .embedding,
                inputPricePer1MTokens: 0.13
            ),
            CloudModelDefinition(
                id: "whisper-1",
                name: "Whisper",
                capability: .speechToText
            )
        ]
    )

    // MARK: - Google Gemini

    public static let googleGemini = ProviderConfiguration(
        id: "google-gemini",
        name: "Google Gemini",
        baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .embedding, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "gemini-2.5-flash",
                name: "Gemini 2.5 Flash",
                capability: .textGeneration,
                contextWindow: 1_000_000,
                inputPricePer1MTokens: 0.10,
                outputPricePer1MTokens: 0.40
            ),
            CloudModelDefinition(
                id: "gemini-2.5-pro",
                name: "Gemini 2.5 Pro",
                capability: .textGeneration,
                contextWindow: 1_000_000,
                inputPricePer1MTokens: 1.25,
                outputPricePer1MTokens: 10.00
            ),
            CloudModelDefinition(
                id: "gemini-2.5-flash",
                name: "Gemini 2.5 Flash (Vision)",
                capability: .vision,
                contextWindow: 1_000_000,
                inputPricePer1MTokens: 0.10,
                outputPricePer1MTokens: 0.40
            ),
            CloudModelDefinition(
                id: "text-embedding-004",
                name: "Text Embedding 004",
                capability: .embedding,
                inputPricePer1MTokens: 0.0
            )
        ]
    )

    // MARK: - Anthropic

    public static let anthropic = ProviderConfiguration(
        id: "anthropic",
        name: "Anthropic",
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        isOpenAICompatible: false,
        supportedCapabilities: [.textGeneration, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "claude-opus-4-6",
                name: "Claude Opus 4.6",
                capability: .textGeneration,
                contextWindow: 200_000,
                inputPricePer1MTokens: 5.00,
                outputPricePer1MTokens: 25.00
            ),
            CloudModelDefinition(
                id: "claude-sonnet-4-5-20250929",
                name: "Claude Sonnet 4.5",
                capability: .textGeneration,
                contextWindow: 200_000,
                inputPricePer1MTokens: 3.00,
                outputPricePer1MTokens: 15.00
            ),
            CloudModelDefinition(
                id: "claude-haiku-4-5-20251001",
                name: "Claude Haiku 4.5",
                capability: .textGeneration,
                contextWindow: 200_000,
                inputPricePer1MTokens: 1.00,
                outputPricePer1MTokens: 5.00
            ),
            CloudModelDefinition(
                id: "claude-sonnet-4-5-20250929",
                name: "Claude Sonnet 4.5 (Vision)",
                capability: .vision,
                contextWindow: 200_000,
                inputPricePer1MTokens: 3.00,
                outputPricePer1MTokens: 15.00
            )
        ]
    )

    // MARK: - Groq

    public static let groq = ProviderConfiguration(
        id: "groq",
        name: "Groq",
        baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .speechToText],
        availableModels: [
            CloudModelDefinition(
                id: "llama-3.3-70b-versatile",
                name: "Llama 3.3 70B Versatile",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 0.59,
                outputPricePer1MTokens: 0.79
            ),
            CloudModelDefinition(
                id: "whisper-large-v3",
                name: "Whisper Large v3",
                capability: .speechToText
            )
        ]
    )

    // MARK: - Together AI

    public static let togetherAI = ProviderConfiguration(
        id: "together-ai",
        name: "Together AI",
        baseURL: URL(string: "https://api.together.xyz/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .embedding, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                name: "Llama 3.3 70B Instruct Turbo",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 0.88,
                outputPricePer1MTokens: 0.88
            )
        ]
    )

    // MARK: - Mistral AI

    public static let mistralAI = ProviderConfiguration(
        id: "mistral-ai",
        name: "Mistral AI",
        baseURL: URL(string: "https://api.mistral.ai/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .embedding, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "mistral-large-latest",
                name: "Mistral Large",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 2.00,
                outputPricePer1MTokens: 6.00
            ),
            CloudModelDefinition(
                id: "mistral-embed",
                name: "Mistral Embed",
                capability: .embedding,
                inputPricePer1MTokens: 0.01
            ),
            CloudModelDefinition(
                id: "pixtral-large-latest",
                name: "Pixtral Large",
                capability: .vision,
                contextWindow: 128_000,
                inputPricePer1MTokens: 2.00,
                outputPricePer1MTokens: 6.00
            )
        ]
    )

    // MARK: - DeepSeek

    public static let deepseek = ProviderConfiguration(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: URL(string: "https://api.deepseek.com/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration],
        availableModels: [
            CloudModelDefinition(
                id: "deepseek-chat",
                name: "DeepSeek V3",
                capability: .textGeneration,
                contextWindow: 64_000,
                inputPricePer1MTokens: 0.27,
                outputPricePer1MTokens: 1.10
            ),
            CloudModelDefinition(
                id: "deepseek-reasoner",
                name: "DeepSeek R1",
                capability: .textGeneration,
                contextWindow: 64_000,
                inputPricePer1MTokens: 0.55,
                outputPricePer1MTokens: 2.19
            )
        ]
    )

    // MARK: - Fireworks AI

    public static let fireworksAI = ProviderConfiguration(
        id: "fireworks-ai",
        name: "Fireworks AI",
        baseURL: URL(string: "https://api.fireworks.ai/inference/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration, .embedding, .speechToText, .vision],
        availableModels: [
            CloudModelDefinition(
                id: "accounts/fireworks/models/llama-v3p3-70b-instruct",
                name: "Llama 3.3 70B Instruct",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 0.90,
                outputPricePer1MTokens: 0.90
            )
        ]
    )

    // MARK: - OpenRouter

    public static let openRouter = ProviderConfiguration(
        id: "openrouter",
        name: "OpenRouter",
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        isOpenAICompatible: true,
        supportedCapabilities: [.textGeneration],
        availableModels: [
            CloudModelDefinition(
                id: "openai/gpt-4o",
                name: "OpenAI GPT-4o (via OpenRouter)",
                capability: .textGeneration,
                contextWindow: 128_000,
                inputPricePer1MTokens: 2.50,
                outputPricePer1MTokens: 10.00
            ),
            CloudModelDefinition(
                id: "anthropic/claude-sonnet-4-5",
                name: "Claude Sonnet 4.5 (via OpenRouter)",
                capability: .textGeneration,
                contextWindow: 200_000,
                inputPricePer1MTokens: 3.00,
                outputPricePer1MTokens: 15.00
            )
        ]
    )
}
