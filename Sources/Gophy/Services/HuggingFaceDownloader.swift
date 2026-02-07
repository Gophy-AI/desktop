import Foundation
import MLXLMCommon
import Hub
import os

private let hfLogger = Logger(subsystem: "com.gophy.app", category: "HuggingFaceDownloader")

public final class HuggingFaceDownloader: @unchecked Sendable, ModelDownloaderProtocol {
    private var isCancelled = false
    private let cancelLock = NSLock()

    public init() {}

    public func download(model: ModelDefinition, to destination: URL) -> AsyncStream<DownloadProgress> {
        setCancelled(false)

        return AsyncStream { continuation in
            Task {
                do {
                    let hubApi = HubApi(downloadBase: destination.deletingLastPathComponent())
                    let repo = Hub.Repo(id: model.huggingFaceID)
                    let estimatedTotalBytes = Int64((model.approximateSizeGB ?? 1.0) * 1_000_000_000)

                    var lastProgress: Double = 0

                    hfLogger.info("Downloading model \(model.huggingFaceID, privacy: .public) to destination \(destination.path, privacy: .public)")
                    hfLogger.info("HubApi downloadBase: \(destination.deletingLastPathComponent().path, privacy: .public)")

                    let snapshotURL = try await hubApi.snapshot(
                        from: repo,
                        matching: [],
                        progressHandler: { progress, totalSize in
                            if self.isCancelledCheck() {
                                return
                            }

                            let totalBytes = totalSize.map { Int64($0) } ?? estimatedTotalBytes
                            let downloadedBytes = Int64(Double(totalBytes) * progress.fractionCompleted)

                            if progress.fractionCompleted > lastProgress {
                                lastProgress = progress.fractionCompleted

                                continuation.yield(DownloadProgress(
                                    model: model,
                                    bytesDownloaded: downloadedBytes,
                                    totalBytes: totalBytes,
                                    status: .downloading
                                ))
                            }
                        }
                    )

                    if self.isCancelledCheck() {
                        try? FileManager.default.removeItem(at: snapshotURL)
                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: 0,
                            totalBytes: 0,
                            status: .cancelled
                        ))
                        continuation.finish()
                        return
                    }

                    hfLogger.info("Snapshot downloaded to: \(snapshotURL.path, privacy: .public)")
                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshotURL.path) {
                        hfLogger.info("Snapshot contents (\(contents.count, privacy: .public) files): \(contents.prefix(20).joined(separator: ", "), privacy: .public)")
                    }

                    if snapshotURL != destination {
                        hfLogger.info("Moving from \(snapshotURL.path, privacy: .public) to \(destination.path, privacy: .public)")
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: snapshotURL, to: destination)
                        hfLogger.info("Move completed")
                    } else {
                        hfLogger.info("Snapshot already at destination, no move needed")
                    }

                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: estimatedTotalBytes,
                        totalBytes: estimatedTotalBytes,
                        status: .completed
                    ))
                    continuation.finish()
                } catch {
                    if self.isCancelledCheck() {
                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: 0,
                            totalBytes: 0,
                            status: .cancelled
                        ))
                    } else {
                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: 0,
                            totalBytes: 0,
                            status: .failed(error)
                        ))
                    }
                    continuation.finish()
                }
            }
        }
    }

    public func cancel() {
        setCancelled(true)
    }

    private func isCancelledCheck() -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return isCancelled
    }

    private func setCancelled(_ value: Bool) {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        isCancelled = value
    }
}
