import Foundation

public protocol ModelRegistryProtocol: Sendable {
    func availableModels() -> [ModelDefinition]
    func isDownloaded(_ model: ModelDefinition) -> Bool
    func downloadPath(for model: ModelDefinition) -> URL
}

public final class ModelRegistry: ModelRegistryProtocol, Sendable {
    public static let shared = ModelRegistry()

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
                id: "qwen2.5-vl-7b-instruct-4bit",
                name: "Qwen2.5-VL 7B Instruct 4-bit",
                type: .ocr,
                huggingFaceID: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            ),
            ModelDefinition(
                id: "nomic-embed-text-v1.5",
                name: "nomic-embed-text v1.5",
                type: .embedding,
                huggingFaceID: "nomic-ai/nomic-embed-text-v1.5",
                approximateSizeGB: 0.3,
                memoryUsageGB: 0.3
            )
        ]
    }

    public func isDownloaded(_ model: ModelDefinition) -> Bool {
        let path = downloadPath(for: model)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path.path) else {
            return false
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            )
            return !contents.isEmpty
        } catch {
            return false
        }
    }

    public func downloadPath(for model: ModelDefinition) -> URL {
        return storageManager.modelsDirectory.appendingPathComponent(model.id)
    }
}
