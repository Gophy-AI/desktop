import Foundation
import WhisperKit

public final class WhisperKitDownloader: @unchecked Sendable, ModelDownloaderProtocol {
    private var isCancelled = false
    private let cancelLock = NSLock()

    public init() {}

    public func download(model: ModelDefinition, to destination: URL) -> AsyncStream<DownloadProgress> {
        setCancelled(false)

        return AsyncStream { continuation in
            Task {
                do {
                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: 0,
                        totalBytes: Int64(model.approximateSizeGB * 1_000_000_000),
                        status: .downloading
                    ))

                    // WhisperKit uses "large-v3-turbo" format, not the full repo ID
                    let modelVariant = "large-v3-turbo"

                    // Download using WhisperKit's built-in download mechanism
                    let downloadedURL = try await WhisperKit.download(
                        variant: modelVariant,
                        downloadBase: destination.deletingLastPathComponent(),
                        useBackgroundSession: false
                    )

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
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: downloadedURL, to: destination)
                    }

                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: Int64(model.approximateSizeGB * 1_000_000_000),
                        totalBytes: Int64(model.approximateSizeGB * 1_000_000_000),
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
