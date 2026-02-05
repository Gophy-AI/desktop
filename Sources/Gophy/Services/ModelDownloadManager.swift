import Foundation

public final class ModelDownloadManager: @unchecked Sendable {
    private let registry: ModelRegistry
    private let downloader: ModelDownloaderProtocol
    private let downloadTasks: NSLock
    private var activeDownloads: [String: Task<Void, Never>]

    public init(
        registry: ModelRegistry = .shared,
        downloader: ModelDownloaderProtocol? = nil
    ) {
        self.registry = registry
        self.downloader = downloader ?? HuggingFaceDownloader()
        self.downloadTasks = NSLock()
        self.activeDownloads = [:]
    }

    public func download(_ model: ModelDefinition) -> AsyncStream<DownloadProgress> {
        if registry.isDownloaded(model) {
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

        return AsyncStream { continuation in
            let task = Task {
                let destination = self.registry.downloadPath(for: model)

                do {
                    try self.ensureSufficientDiskSpace(for: model)

                    let downloadStream = self.downloader.download(model: model, to: destination)

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

        downloader.cancel()
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

        let requiredBytes = Int64(model.approximateSizeGB * 1_000_000_000)
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
