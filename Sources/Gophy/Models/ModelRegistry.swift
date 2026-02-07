import Foundation
import os

private let registryLogger = Logger(subsystem: "com.gophy.app", category: "ModelRegistry")

public protocol ModelRegistryProtocol: Sendable {
    func availableModels() -> [ModelDefinition]
    func isDownloaded(_ model: ModelDefinition) -> Bool
    func downloadPath(for model: ModelDefinition) -> URL
}

public final class ModelRegistry: ModelRegistryProtocol, Sendable {
    public static let shared: ModelRegistryProtocol = DynamicModelRegistry()

    private let storageManager: StorageManager

    public init(storageManager: StorageManager = .shared) {
        self.storageManager = storageManager
    }

    public func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.5
            ),
            ModelDefinition(
                id: "qwen2.5-7b-instruct-4bit",
                name: "Qwen2.5 7B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            ),
            ModelDefinition(
                id: "qwen3-8b-instruct-4bit",
                name: "Qwen3 8B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen3-8B-4bit",
                approximateSizeGB: 4.5,
                memoryUsageGB: 4.5
            ),
            ModelDefinition(
                id: "qwen2.5-vl-7b-instruct-4bit",
                name: "Qwen2.5-VL 7B Instruct 4-bit",
                type: .ocr,
                huggingFaceID: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                approximateSizeGB: 5.3,
                memoryUsageGB: 5.5
            ),
            ModelDefinition(
                id: "multilingual-e5-small",
                name: "Multilingual E5 Small (Embeddings)",
                type: .embedding,
                huggingFaceID: "intfloat/multilingual-e5-small",
                approximateSizeGB: 0.47,
                memoryUsageGB: 0.5
            )
        ]
    }

    public func isDownloaded(_ model: ModelDefinition) -> Bool {
        let primaryPath = downloadPath(for: model)
        registryLogger.info("isDownloaded(\(model.id, privacy: .public)): checking primary=\(primaryPath.path, privacy: .public)")

        if isModelAt(primaryPath) {
            registryLogger.info("isDownloaded(\(model.id, privacy: .public)): found at primary path")
            return true
        }
        if let altPath = alternativeDownloadPath(for: model) {
            registryLogger.info("isDownloaded(\(model.id, privacy: .public)): checking alt=\(altPath.path, privacy: .public)")
            if isModelAt(altPath) {
                registryLogger.info("isDownloaded(\(model.id, privacy: .public)): found at alternative path")
                return true
            }
        }
        registryLogger.warning("isDownloaded(\(model.id, privacy: .public)): NOT FOUND at any path")
        return false
    }

    private func isModelAt(_ path: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path.path) else {
            registryLogger.info("isModelAt: directory does not exist: \(path.path, privacy: .public)")
            return false
        }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            let fileNames = contents.map { $0.lastPathComponent }
            registryLogger.info("isModelAt: \(path.lastPathComponent, privacy: .public) top-level (\(contents.count, privacy: .public) items): \(fileNames.joined(separator: ", "), privacy: .public)")

            let hasWeights = contents.contains { url in
                url.pathExtension == "safetensors" || url.pathExtension == "mlmodelc"
            }
            if hasWeights {
                registryLogger.info("isModelAt: found weights at top level")
                return true
            }

            // Check one level of subdirectories
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
                            registryLogger.info("isModelAt: found weights in subdirectory \(url.lastPathComponent, privacy: .public)")
                            return true
                        }
                    }
                }
            }

            registryLogger.info("isModelAt: no weights found at \(path.lastPathComponent, privacy: .public)")
            return false
        } catch {
            registryLogger.error("isModelAt: failed to list directory \(path.path, privacy: .public): \(error, privacy: .public)")
            return false
        }
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

    private func alternativeDownloadPath(for model: ModelDefinition) -> URL? {
        return storageManager.alternativeModelsDirectory?.appendingPathComponent(model.id)
    }
}
