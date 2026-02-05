import XCTest
@testable import Gophy

final class ModelDownloadManagerTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var modelRegistry: ModelRegistry!
    var downloadManager: ModelDownloadManager!
    var mockDownloader: MockModelDownloader!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        storageManager = StorageManager(baseDirectory: tempDirectory)
        modelRegistry = ModelRegistry(storageManager: storageManager)
        mockDownloader = MockModelDownloader()
        downloadManager = ModelDownloadManager(
            registry: modelRegistry,
            downloader: mockDownloader
        )
    }

    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try await super.tearDown()
    }

    func testDownloadEmitsProgressUpdates() async throws {
        let model = modelRegistry.availableModels().first!
        mockDownloader.shouldSucceed = true

        var progressUpdates: [DownloadProgress] = []
        let stream = downloadManager.download(model)

        for await progress in stream {
            progressUpdates.append(progress)
            if case .completed = progress.status {
                break
            }
        }

        XCTAssertGreaterThan(progressUpdates.count, 0, "Should emit at least one progress update")

        let lastProgress = progressUpdates.last
        XCTAssertNotNil(lastProgress)

        if case .completed = lastProgress?.status {
            XCTAssertTrue(true, "Last progress should be completed")
        } else {
            XCTFail("Last progress should have completed status")
        }
    }

    func testCancellationStopsDownload() async throws {
        let model = modelRegistry.availableModels().first!
        mockDownloader.shouldSucceed = true
        mockDownloader.delayBetweenUpdates = 0.02

        let manager = downloadManager!
        let stream = manager.download(model)

        var progressCount = 0
        var sawCancelled = false

        let downloadTask = Task {
            for await progress in stream {
                progressCount += 1
                if case .cancelled = progress.status {
                    sawCancelled = true
                    break
                }
                if case .completed = progress.status {
                    break
                }

                if progressCount == 2 {
                    manager.cancel(model)
                }
            }
        }

        await downloadTask.value

        XCTAssertTrue(sawCancelled || progressCount < 11, "Download should be cancelled or stopped early")
    }

    func testAlreadyDownloadedModelReturnsImmediately() async throws {
        let model = modelRegistry.availableModels().first!

        let downloadPath = modelRegistry.downloadPath(for: model)
        try FileManager.default.createDirectory(at: downloadPath, withIntermediateDirectories: true)
        let configFile = downloadPath.appendingPathComponent("config.json")
        try "{}".write(to: configFile, atomically: true, encoding: .utf8)

        var progressUpdates: [DownloadProgress] = []
        let stream = downloadManager.download(model)

        for await progress in stream {
            progressUpdates.append(progress)
            if case .completed = progress.status {
                break
            }
        }

        XCTAssertEqual(progressUpdates.count, 1, "Should emit exactly one progress update for already downloaded model")

        if let firstProgress = progressUpdates.first {
            if case .completed = firstProgress.status {
                XCTAssertTrue(true, "Should immediately return completed status")
            } else {
                XCTFail("Should have completed status")
            }
        } else {
            XCTFail("Should have at least one progress update")
        }

        XCTAssertFalse(mockDownloader.downloadCalled, "Should not call downloader for already downloaded model")
    }

    func testDownloadFailureEmitsError() async throws {
        let model = modelRegistry.availableModels().first!
        mockDownloader.shouldSucceed = false

        var lastStatus: DownloadStatus?
        let stream = downloadManager.download(model)

        for await progress in stream {
            lastStatus = progress.status
            if case .failed = progress.status {
                break
            }
        }

        XCTAssertNotNil(lastStatus)
        if case .failed = lastStatus {
            XCTAssertTrue(true, "Should emit failed status on download error")
        } else {
            XCTFail("Should have failed status")
        }
    }

    func testIsDownloadingReturnsTrueWhileDownloadIsInProgress() async throws {
        let model = modelRegistry.availableModels().first!
        mockDownloader.shouldSucceed = true
        mockDownloader.delayBetweenUpdates = 0.1

        let manager = downloadManager!

        XCTAssertFalse(manager.isDownloading(model), "Should not be downloading initially")

        let stream = manager.download(model)

        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(manager.isDownloading(model), "Should be downloading after starting")

        for await progress in stream {
            if case .completed = progress.status {
                break
            }
        }

        XCTAssertFalse(manager.isDownloading(model), "Should not be downloading after completion")
    }

    func testProgressFractionComputedCorrectly() async throws {
        let progress = DownloadProgress(
            model: modelRegistry.availableModels().first!,
            bytesDownloaded: 50,
            totalBytes: 100,
            status: .downloading
        )

        XCTAssertEqual(progress.fractionCompleted, 0.5, accuracy: 0.001, "Fraction should be 0.5 when half downloaded")
    }

    func testProgressFractionIsZeroWhenTotalBytesIsZero() async throws {
        let progress = DownloadProgress(
            model: modelRegistry.availableModels().first!,
            bytesDownloaded: 0,
            totalBytes: 0,
            status: .downloading
        )

        XCTAssertEqual(progress.fractionCompleted, 0, "Fraction should be 0 when totalBytes is 0")
    }
}

final class MockModelDownloader: @unchecked Sendable, ModelDownloaderProtocol {
    var shouldSucceed = true
    var delayBetweenUpdates: TimeInterval = 0.01
    var downloadCalled = false
    private var isCancelled = false

    func download(model: ModelDefinition, to destination: URL) -> AsyncStream<DownloadProgress> {
        downloadCalled = true
        isCancelled = false

        return AsyncStream { continuation in
            Task {
                if shouldSucceed {
                    let totalBytes: Int64 = 1000

                    for i in 0...10 {
                        if isCancelled {
                            continuation.yield(DownloadProgress(
                                model: model,
                                bytesDownloaded: Int64(i * 100),
                                totalBytes: totalBytes,
                                status: .cancelled
                            ))
                            continuation.finish()
                            return
                        }

                        let bytesDownloaded = Int64(i * 100)
                        let status: DownloadStatus = i == 10 ? .completed : .downloading

                        continuation.yield(DownloadProgress(
                            model: model,
                            bytesDownloaded: bytesDownloaded,
                            totalBytes: totalBytes,
                            status: status
                        ))

                        if i < 10 {
                            try? await Task.sleep(nanoseconds: UInt64(delayBetweenUpdates * 1_000_000_000))
                        }
                    }
                } else {
                    continuation.yield(DownloadProgress(
                        model: model,
                        bytesDownloaded: 0,
                        totalBytes: 1000,
                        status: .failed(MockDownloadError.downloadFailed)
                    ))
                }

                continuation.finish()
            }
        }
    }

    func cancel() {
        isCancelled = true
    }
}

enum MockDownloadError: Error {
    case downloadFailed
}
