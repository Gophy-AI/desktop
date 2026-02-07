import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "ModelDownloadManager")

public final class ModelDownloadManager: @unchecked Sendable {
    private let registry: ModelRegistryProtocol
    private let huggingFaceDownloader: ModelDownloaderProtocol
    private let whisperKitDownloader: ModelDownloaderProtocol
    private let downloadTasks: NSLock
    private var activeDownloads: [String: Task<Void, Never>]

    public init(
        registry: ModelRegistryProtocol = ModelRegistry.shared,
        downloader: ModelDownloaderProtocol? = nil,
        whisperKitDownloader: ModelDownloaderProtocol? = nil
    ) {
        self.registry = registry
        self.huggingFaceDownloader = downloader ?? HuggingFaceDownloader()
        self.whisperKitDownloader = whisperKitDownloader ?? WhisperKitDownloader()
        self.downloadTasks = NSLock()
        self.activeDownloads = [:]
    }

    private func downloader(for model: ModelDefinition) -> ModelDownloaderProtocol {
        // Use WhisperKitDownloader for STT models, HuggingFaceDownloader for others
        if model.type == .stt {
            return whisperKitDownloader
        }
        return huggingFaceDownloader
    }

    public func download(_ model: ModelDefinition) -> AsyncStream<DownloadProgress> {
        logger.info("Download requested for model: \(model.id), type: \(model.type.rawValue)")

        if registry.isDownloaded(model) {
            logger.info("Model already downloaded, returning completed status")
            return AsyncStream { continuation in
                continuation.yield(DownloadProgress(
                    model: model,
                    bytesDownloaded: 0,
                    totalBytes: 0,
                    status: .completed
                ))
                continuation.finish()
            }
        }

        logger.info("Model not downloaded, starting download")

        return AsyncStream { continuation in
            let task = Task {
                let destination = self.registry.downloadPath(for: model)
                logger.info("Download destination: \(destination.path)")

                do {
                    try self.ensureSufficientDiskSpace(for: model)
                    logger.info("Disk space check passed")

                    let selectedDownloader = self.downloader(for: model)
                    logger.info("Using downloader: \(type(of: selectedDownloader))")

                    let downloadStream = selectedDownloader.download(model: model, to: destination)

                    for await progress in downloadStream {
                        continuation.yield(progress)

                        if progress.status.isTerminal {
                            self.removeActiveDownload(for: model)
                            continuation.finish()
                            return
                        }
                    }

                    self.removeActiveDownload(for: model)
                    continuation.finish()
                } catch {
                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        status: .failed(error)
                    ))
                    self.removeActiveDownload(for: model)
                    continuation.finish()
                }
            }

            self.setActiveDownload(task: task, for: model)
        }
    }

    public func cancel(_ model: ModelDefinition) {
        downloadTasks.lock()
        defer { downloadTasks.unlock() }

        if let task = activeDownloads[model.id] {
            task.cancel()
            activeDownloads.removeValue(forKey: model.id)
        }

        downloader(for: model).cancel()
    }

    public func isDownloading(_ model: ModelDefinition) -> Bool {
        downloadTasks.lock()
        defer { downloadTasks.unlock() }

        return activeDownloads[model.id] != nil
    }

    private func setActiveDownload(task: Task<Void, Never>, for model: ModelDefinition) {
        downloadTasks.lock()
        defer { downloadTasks.unlock() }

        activeDownloads[model.id] = task
    }

    private func removeActiveDownload(for model: ModelDefinition) {
        downloadTasks.lock()
        defer { downloadTasks.unlock() }

        activeDownloads.removeValue(forKey: model.id)
    }

    private func ensureSufficientDiskSpace(for model: ModelDefinition) throws {
        let fileManager = FileManager.default
        guard let resourceValues = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = resourceValues[.systemFreeSize] as? Int64 else {
            return
        }

        // Skip check if model size is unknown
        guard let sizeGB = model.approximateSizeGB else {
            return
        }

        let requiredBytes = Int64(sizeGB * 1_000_000_000)
        let bufferBytes = Int64(1_000_000_000)

        if freeSpace < (requiredBytes + bufferBytes) {
            throw ModelDownloadError.insufficientDiskSpace(
                required: requiredBytes,
                available: freeSpace
            )
        }
    }
}

public enum ModelDownloadError: Error, LocalizedError {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case downloadFailed(underlying: Error)
    case invalidDestination

    public var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let required, let available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return "Insufficient disk space. Required: \(String(format: "%.2f", requiredGB))GB, Available: \(String(format: "%.2f", availableGB))GB"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .invalidDestination:
            return "Invalid download destination"
        }
    }
}
