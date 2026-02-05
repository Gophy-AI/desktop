import Foundation

public protocol ModelDownloaderProtocol: Sendable {
    func download(model: ModelDefinition, to destination: URL) -> AsyncStream<DownloadProgress>
    func cancel()
}
