import Foundation
import Observation

@MainActor
@Observable
final class ModelManagerViewModel {
    private let registry: ModelRegistryProtocol
    private let downloadManager: ModelDownloadManager
    private let storageManager: StorageManager

    var models: [ModelDefinition] = []
    var downloadProgress: [String: DownloadProgress] = [:]
    var totalDiskUsageGB: Double = 0.0
    var errorMessage: String?
    var searchQuery: String = ""
    var selectedTypeFilter: ModelType?

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var allModels: [ModelDefinition] = []

    init(
        registry: ModelRegistryProtocol = ModelRegistry.shared,
        downloadManager: ModelDownloadManager = ModelDownloadManager(),
        storageManager: StorageManager = .shared
    ) {
        self.registry = registry
        self.downloadManager = downloadManager
        self.storageManager = storageManager

        loadModels()
        calculateDiskUsage()
    }

    func loadModels() {
        allModels = registry.availableModels()
        applyFilters()
    }

    func applyFilters() {
        var filtered = allModels

        // Apply search query
        if !searchQuery.isEmpty {
            if let dynamicRegistry = registry as? DynamicModelRegistry {
                filtered = dynamicRegistry.search(query: searchQuery)
            } else {
                let lowercaseQuery = searchQuery.lowercased()
                filtered = filtered.filter { model in
                    model.name.lowercased().contains(lowercaseQuery) ||
                    model.huggingFaceID.lowercased().contains(lowercaseQuery)
                }
            }
        }

        // Apply type filter
        if let typeFilter = selectedTypeFilter {
            filtered = filtered.filter { $0.type == typeFilter }
        }

        models = filtered
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        applyFilters()
    }

    func updateTypeFilter(_ type: ModelType?) {
        selectedTypeFilter = type
        applyFilters()
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return registry.isDownloaded(model)
    }

    func isDownloading(_ model: ModelDefinition) -> Bool {
        return downloadProgress[model.id]?.status.isTerminal == false
    }

    func downloadSpeed(for model: ModelDefinition) -> Double? {
        guard let progress = downloadProgress[model.id],
              case .downloading = progress.status,
              progress.totalBytes > 0 else {
            return nil
        }

        return Double(progress.bytesDownloaded) / max(1.0, Date().timeIntervalSince1970)
    }

    func downloadModel(_ model: ModelDefinition) {
        errorMessage = nil

        let task = Task {
            let progressStream = downloadManager.download(model)

            for await progress in progressStream {
                self.downloadProgress[model.id] = progress

                if case .completed = progress.status {
                    self.calculateDiskUsage()
                } else if case .failed(let error) = progress.status {
                    self.errorMessage = error.localizedDescription
                }
            }

            downloadTasks.removeValue(forKey: model.id)
        }

        downloadTasks[model.id] = task
    }

    func cancelDownload(_ model: ModelDefinition) {
        downloadManager.cancel(model)
        downloadTasks[model.id]?.cancel()
        downloadTasks.removeValue(forKey: model.id)
        downloadProgress.removeValue(forKey: model.id)
    }

    func deleteModel(_ model: ModelDefinition) {
        let path = registry.downloadPath(for: model)
        let fileManager = FileManager.default

        do {
            try fileManager.removeItem(at: path)
            calculateDiskUsage()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    func calculateDiskUsage() {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        for model in models {
            let path = registry.downloadPath(for: model)

            if let enumerator = fileManager.enumerator(at: path, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
        }

        totalDiskUsageGB = Double(totalSize) / 1_000_000_000
    }

    var hasDownloadedModels: Bool {
        models.contains { registry.isDownloaded($0) }
    }
}
