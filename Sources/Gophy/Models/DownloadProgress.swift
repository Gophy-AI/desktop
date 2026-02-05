import Foundation

public struct DownloadProgress: Sendable {
    public let model: ModelDefinition
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let status: DownloadStatus

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }

    public init(
        model: ModelDefinition,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        status: DownloadStatus
    ) {
        self.model = model
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.status = status
    }
}

public enum DownloadStatus: Sendable {
    case downloading
    case completed
    case failed(Error)
    case cancelled
}

extension DownloadStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .downloading:
            return false
        }
    }
}
