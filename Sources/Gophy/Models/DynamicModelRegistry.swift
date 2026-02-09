import Foundation
import MLXLLM
import MLXVLM
import MLXEmbedders
import MLXLMCommon
import os

private let logger = Logger(subsystem: "com.gophy.app", category: "DynamicModelRegistry")

public final class DynamicModelRegistry: ModelRegistryProtocol, Sendable {
    private let storageManager: StorageManager
    private let allModels: [ModelDefinition]

    public init(storageManager: StorageManager = .shared) {
        self.storageManager = storageManager

        var models: [ModelDefinition] = []

        // 1. Add curated models first (hardcoded with known sizes)
        models.append(contentsOf: [
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.6,
                memoryUsageGB: 2.0,
                source: .curated
            ),
            ModelDefinition(
                id: "qwen2.5-7b-instruct-4bit",
                name: "Qwen2.5 7B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                approximateSizeGB: 4.3,
                memoryUsageGB: 5.5,
                source: .curated
            ),
            ModelDefinition(
                id: "qwen3-8b-instruct-4bit",
                name: "Qwen3 8B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen3-8B-4bit",
                approximateSizeGB: 4.6,
                memoryUsageGB: 6.0,
                source: .curated
            ),
            ModelDefinition(
                id: "qwen2.5-vl-7b-instruct-4bit",
                name: "Qwen2.5-VL 7B Instruct 4-bit",
                type: .ocr,
                huggingFaceID: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                approximateSizeGB: 5.6,
                memoryUsageGB: 7.0,
                source: .curated
            ),
            ModelDefinition(
                id: "multilingual-e5-small",
                name: "Multilingual E5 Small (Embeddings)",
                type: .embedding,
                huggingFaceID: "intfloat/multilingual-e5-small",
                approximateSizeGB: 0.9,
                memoryUsageGB: 1.0,
                source: .curated
            ),
            // TTS models
            ModelDefinition(
                id: "soprano-80m-bf16",
                name: "Soprano 80M",
                type: .tts,
                huggingFaceID: "mlx-community/Soprano-80M-bf16",
                approximateSizeGB: 0.2,
                memoryUsageGB: 0.3,
                source: .curated
            ),
            ModelDefinition(
                id: "marvis-tts-250m-8bit",
                name: "Marvis TTS 250M",
                type: .tts,
                huggingFaceID: "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit",
                approximateSizeGB: 0.7,
                memoryUsageGB: 0.9,
                source: .curated
            ),
            ModelDefinition(
                id: "orpheus-3b-bf16",
                name: "Orpheus 3B",
                type: .tts,
                huggingFaceID: "mlx-community/orpheus-3b-0.1-ft-bf16",
                approximateSizeGB: 6.6,
                memoryUsageGB: 7.5,
                source: .curated
            ),
            ModelDefinition(
                id: "vyvotts-en-beta-4bit",
                name: "VyvoTTS EN",
                type: .tts,
                huggingFaceID: "mlx-community/VyvoTTS-EN-Beta-4bit",
                approximateSizeGB: 1.0,
                memoryUsageGB: 1.5,
                source: .curated
            ),
            ModelDefinition(
                id: "pocket-tts",
                name: "PocketTTS",
                type: .tts,
                huggingFaceID: "mlx-community/pocket-tts",
                approximateSizeGB: 0.2,
                memoryUsageGB: 0.3,
                source: .curated
            ),
            // MLX STT models (audioRegistry)
            ModelDefinition(
                id: "glmasr-large-v2",
                name: "GLM-ASR Large v2",
                type: .stt,
                huggingFaceID: "THUDM/glm-4-voice-tokenizer",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.8,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "lasr-ctc-large",
                name: "LASR CTC Large",
                type: .stt,
                huggingFaceID: "DeweyReed/LASR-CTC-large-v1",
                approximateSizeGB: 1.2,
                memoryUsageGB: 1.5,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "whisper-mlx-large-v3",
                name: "Whisper Large v3 (MLX)",
                type: .stt,
                huggingFaceID: "mlx-community/whisper-large-v3",
                approximateSizeGB: 3.1,
                memoryUsageGB: 3.5,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "parakeet-ctc-1.1b",
                name: "Parakeet CTC 1.1B",
                type: .stt,
                huggingFaceID: "nvidia/parakeet-ctc-1.1b",
                approximateSizeGB: 4.3,
                memoryUsageGB: 5.0,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "qwen3-asr",
                name: "Qwen3 ASR",
                type: .stt,
                huggingFaceID: "Qwen/Qwen3-ASR",
                approximateSizeGB: 4.7,
                memoryUsageGB: 6.0,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "wav2vec-large-960h",
                name: "Wav2Vec2 Large 960h",
                type: .stt,
                huggingFaceID: "facebook/wav2vec2-large-960h-lv60-self",
                approximateSizeGB: 1.3,
                memoryUsageGB: 1.5,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "voxtral-mini",
                name: "Voxtral Mini",
                type: .stt,
                huggingFaceID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                approximateSizeGB: 9.4,
                memoryUsageGB: 10.5,
                source: .audioRegistry
            ),
            ModelDefinition(
                id: "voxtral-mini-4b-realtime",
                name: "Voxtral Mini 4B Realtime",
                type: .stt,
                huggingFaceID: "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
                approximateSizeGB: 3.6,
                memoryUsageGB: 6.0,
                source: .audioRegistry
            )
        ])

        // 2. Add LLM models from LLMRegistry
        let llmModels = LLMRegistry.shared.models
        for llmConfig in llmModels {
            let modelId = Self.sanitizeModelId(llmConfig.name)
            // Skip if already in curated list
            if !models.contains(where: { $0.id == modelId || $0.huggingFaceID == llmConfig.name }) {
                models.append(ModelDefinition(
                    id: modelId,
                    name: Self.displayName(from: llmConfig.name),
                    type: .textGen,
                    huggingFaceID: llmConfig.name,
                    approximateSizeGB: nil,
                    memoryUsageGB: nil,
                    source: .llmRegistry
                ))
            }
        }

        // 3. Add VLM models from VLMRegistry
        let vlmModels = VLMRegistry.shared.models
        for vlmConfig in vlmModels {
            let modelId = Self.sanitizeModelId(vlmConfig.name)
            // Skip if already in curated list
            if !models.contains(where: { $0.id == modelId || $0.huggingFaceID == vlmConfig.name }) {
                models.append(ModelDefinition(
                    id: modelId,
                    name: Self.displayName(from: vlmConfig.name),
                    type: .ocr,
                    huggingFaceID: vlmConfig.name,
                    approximateSizeGB: nil,
                    memoryUsageGB: nil,
                    source: .vlmRegistry
                ))
            }
        }

        // 4. Add Embedder models from MLXEmbedders
        // Note: This is @MainActor, so we access synchronously if on main thread
        // For simplicity in init, we'll use Task to get embedder models
        // Actually, we can't use async in init, so we'll enumerate synchronously
        // The embedder models list is static and doesn't require async
        let embedderConfigs = Self.getEmbedderModels()
        for embedderConfig in embedderConfigs {
            let modelId = Self.sanitizeModelId(embedderConfig.name)
            // Skip if already in curated list
            if !models.contains(where: { $0.id == modelId || $0.huggingFaceID == embedderConfig.name }) {
                models.append(ModelDefinition(
                    id: modelId,
                    name: Self.displayName(from: embedderConfig.name),
                    type: .embedding,
                    huggingFaceID: embedderConfig.name,
                    approximateSizeGB: nil,
                    memoryUsageGB: nil,
                    source: .embeddersRegistry
                ))
            }
        }

        self.allModels = models
        logger.info("DynamicModelRegistry initialized with \(models.count) models")
    }

    // MARK: - ModelRegistryProtocol

    public func availableModels() -> [ModelDefinition] {
        return allModels
    }

    public func isDownloaded(_ model: ModelDefinition) -> Bool {
        let primaryPath = downloadPath(for: model)
        logger.info("isDownloaded(\(model.id, privacy: .public)): checking primary=\(primaryPath.path, privacy: .public)")

        if isModelAt(primaryPath) {
            logger.info("isDownloaded(\(model.id, privacy: .public)): found at primary path")
            return true
        }
        if let altPath = alternativeDownloadPath(for: model) {
            logger.info("isDownloaded(\(model.id, privacy: .public)): checking alt=\(altPath.path, privacy: .public)")
            if isModelAt(altPath) {
                logger.info("isDownloaded(\(model.id, privacy: .public)): found at alternative path")
                return true
            }
        }
        logger.warning("isDownloaded(\(model.id, privacy: .public)): NOT FOUND at any path")
        return false
    }

    public func downloadPath(for model: ModelDefinition) -> URL {
        // If model exists in alternative path but not primary, return alternative
        let primaryPath = storageManager.modelsDirectory.appendingPathComponent(model.id)
        if let altPath = alternativeDownloadPath(for: model),
           !isModelAt(primaryPath) && isModelAt(altPath) {
            return altPath
        }
        return primaryPath
    }

    // MARK: - Search/Filter

    public func search(query: String) -> [ModelDefinition] {
        let lowercaseQuery = query.lowercased()
        return allModels.filter { model in
            model.name.lowercased().contains(lowercaseQuery) ||
            model.huggingFaceID.lowercased().contains(lowercaseQuery)
        }
    }

    public func filterByType(_ type: ModelType) -> [ModelDefinition] {
        return allModels.filter { $0.type == type }
    }

    // MARK: - Private Helpers

    private func isModelAt(_ path: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path.path) else {
            logger.info("isModelAt: directory does not exist: \(path.path, privacy: .public)")
            return false
        }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            let fileNames = contents.map { $0.lastPathComponent }
            logger.info("isModelAt: \(path.lastPathComponent, privacy: .public) top-level (\(contents.count, privacy: .public) items): \(fileNames.joined(separator: ", "), privacy: .public)")

            // Check top-level first
            let hasWeights = contents.contains { url in
                url.pathExtension == "safetensors" || url.pathExtension == "mlmodelc"
            }
            if hasWeights {
                logger.info("isModelAt: found weights at top level")
                return true
            }

            // Check one level of subdirectories (HuggingFace snapshot structure)
            for url in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let subContents = try? fileManager.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: .skipsHiddenFiles
                    ) {
                        let subHasWeights = subContents.contains { subUrl in
                            subUrl.pathExtension == "safetensors" || subUrl.pathExtension == "mlmodelc"
                        }
                        if subHasWeights {
                            logger.info("isModelAt: found weights in subdirectory \(url.lastPathComponent, privacy: .public)")
                            return true
                        }
                    }
                }
            }

            logger.info("isModelAt: no weights found at \(path.lastPathComponent, privacy: .public)")
            return false
        } catch {
            logger.error("isModelAt: failed to list directory \(path.path, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }

    private func alternativeDownloadPath(for model: ModelDefinition) -> URL? {
        return storageManager.alternativeModelsDirectory?.appendingPathComponent(model.id)
    }

    private static func sanitizeModelId(_ name: String) -> String {
        // Convert HuggingFace ID to filesystem-safe ID
        // e.g., "mlx-community/Qwen3-8B-4bit" -> "mlx-community-qwen3-8b-4bit"
        return name
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
    }

    private static func displayName(from huggingFaceID: String) -> String {
        // Extract display name from HuggingFace ID
        // e.g., "mlx-community/Qwen3-8B-4bit" -> "Qwen3 8B 4-bit"
        let components = huggingFaceID.split(separator: "/")
        guard let modelName = components.last else {
            return huggingFaceID
        }
        // Replace hyphens with spaces for better readability
        return String(modelName).replacingOccurrences(of: "-", with: " ")
    }

    private static func getEmbedderModels() -> [EmbedderModelInfo] {
        // We need to enumerate embedder models synchronously
        // The MLXEmbedders.ModelConfiguration.models is @MainActor
        // We'll return the hardcoded list from the research
        return [
            EmbedderModelInfo(name: "TaylorAI/bge-micro-v2"),
            EmbedderModelInfo(name: "TaylorAI/gte-tiny"),
            EmbedderModelInfo(name: "sentence-transformers/all-MiniLM-L6-v2"),
            EmbedderModelInfo(name: "Snowflake/snowflake-arctic-embed-xs"),
            EmbedderModelInfo(name: "sentence-transformers/all-MiniLM-L12-v2"),
            EmbedderModelInfo(name: "BAAI/bge-small-en-v1.5"),
            EmbedderModelInfo(name: "intfloat/multilingual-e5-small"),
            EmbedderModelInfo(name: "BAAI/bge-base-en-v1.5"),
            EmbedderModelInfo(name: "nomic-ai/nomic-embed-text-v1"),
            EmbedderModelInfo(name: "nomic-ai/nomic-embed-text-v1.5"),
            EmbedderModelInfo(name: "BAAI/bge-large-en-v1.5"),
            EmbedderModelInfo(name: "Snowflake/snowflake-arctic-embed-l"),
            EmbedderModelInfo(name: "BAAI/bge-m3"),
            EmbedderModelInfo(name: "mixedbread-ai/mxbai-embed-large-v1"),
            EmbedderModelInfo(name: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
        ]
    }
}

// Helper struct to represent embedder model info
private struct EmbedderModelInfo {
    let name: String
}
