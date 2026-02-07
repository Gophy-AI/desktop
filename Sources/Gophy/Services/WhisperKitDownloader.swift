import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "WhisperKitDownloader")

public final class WhisperKitDownloader: @unchecked Sendable, ModelDownloaderProtocol {
    private var isCancelled = false
    private let cancelLock = NSLock()

    public init() {
        logger.info("WhisperKitDownloader initialized")
    }

    public func download(model: ModelDefinition, to destination: URL) -> AsyncStream<DownloadProgress> {
        setCancelled(false)
        logger.info("Starting download for model: \(model.id, privacy: .public) to \(destination.path, privacy: .public)")

        return AsyncStream { continuation in
            Task {
                do {
                    logger.info("Emitting initial downloading status")
                    let estimatedTotalBytes = Int64((model.approximateSizeGB ?? 1.5) * 1_000_000_000)
                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: 0,
                        totalBytes: estimatedTotalBytes,
                        status: .downloading
                    ))

                    // WhisperKit uses full variant names like "openai_whisper-large-v3_turbo"
                    let modelVariant = "openai_whisper-large-v3_turbo"
                    let downloadBase = destination.deletingLastPathComponent()

                    logger.info("Calling WhisperKit.download(variant: \(modelVariant, privacy: .public), downloadBase: \(downloadBase.path, privacy: .public))")

                    // Download using WhisperKit's built-in download mechanism with progress callback
                    let downloadedURL = try await WhisperKit.download(
                        variant: modelVariant,
                        downloadBase: downloadBase,
                        useBackgroundSession: false,
                        progressCallback: { progress in
                            let downloadedBytes = Int64(Double(estimatedTotalBytes) * progress.fractionCompleted)
                            logger.info("Download progress: \(Int(progress.fractionCompleted * 100), privacy: .public)%")
                            continuation.yield(DownloadProgress(
                                model: model,
                                bytesDownloaded: downloadedBytes,
                                totalBytes: estimatedTotalBytes,
                                status: .downloading
                            ))
                        }
                    )

                    logger.info("WhisperKit.download completed, downloadedURL: \(downloadedURL.path, privacy: .public)")

                    if self.isCancelledCheck() {
                        try? FileManager.default.removeItem(at: downloadedURL)
                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: 0,
                            totalBytes: 0,
                            status: .cancelled
                        ))
                        continuation.finish()
                        return
                    }

                    // Move to expected destination if needed
                    if downloadedURL != destination {
                        logger.info("Moving from \(downloadedURL.path) to \(destination.path)")
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: downloadedURL, to: destination)
                    }

                    logger.info("Download completed successfully")
                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: Int64((model.approximateSizeGB ?? 1.5) * 1_000_000_000),
                        totalBytes: Int64((model.approximateSizeGB ?? 1.5) * 1_000_000_000),
                        status: .completed
                    ))
                    continuation.finish()
                } catch {
                    logger.error("Download failed with error: \(error.localizedDescription, privacy: .public)")
                    if self.isCancelledCheck() {
                        logger.info("Download was cancelled")
                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: 0,
                            totalBytes: 0,
                            status: .cancelled
                        ))
                    } else {
                        logger.error("Emitting failed status")
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
