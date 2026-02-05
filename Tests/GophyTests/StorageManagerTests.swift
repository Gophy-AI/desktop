import XCTest
import Foundation
@testable import Gophy

final class StorageManagerTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testModelsDirectoryPath() throws {
        let modelsDirectory = storageManager.modelsDirectory
        let expectedPath = tempDirectory.appendingPathComponent("models").path
        XCTAssertEqual(modelsDirectory.path, expectedPath, "modelsDirectory should be under base/models")
    }

    func testDatabaseDirectoryPath() throws {
        let databaseDirectory = storageManager.databaseDirectory
        let expectedPath = tempDirectory.appendingPathComponent("data").path
        XCTAssertEqual(databaseDirectory.path, expectedPath, "databaseDirectory should be under base/data")
    }

    func testLogsDirectoryPath() throws {
        let logsDirectory = storageManager.logsDirectory
        let expectedPath = tempDirectory.appendingPathComponent("logs").path
        XCTAssertEqual(logsDirectory.path, expectedPath, "logsDirectory should be under base/logs")
    }

    func testDirectoriesCreatedOnInit() throws {
        let fileManager = FileManager.default

        XCTAssertTrue(fileManager.fileExists(atPath: tempDirectory.path), "Base directory should be created")
        XCTAssertTrue(fileManager.fileExists(atPath: storageManager.modelsDirectory.path), "Models directory should be created")
        XCTAssertTrue(fileManager.fileExists(atPath: storageManager.databaseDirectory.path), "Database directory should be created")
        XCTAssertTrue(fileManager.fileExists(atPath: storageManager.logsDirectory.path), "Logs directory should be created")

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: storageManager.modelsDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(isDirectory.boolValue, "Models path should be a directory")

        fileManager.fileExists(atPath: storageManager.databaseDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(isDirectory.boolValue, "Database path should be a directory")

        fileManager.fileExists(atPath: storageManager.logsDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(isDirectory.boolValue, "Logs path should be a directory")
    }

    func testSharedInstanceUsesApplicationSupport() throws {
        let shared = StorageManager.shared
        let expectedBasePath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Gophy").path

        XCTAssertTrue(shared.modelsDirectory.path.hasPrefix(expectedBasePath), "Shared instance should use Application Support/Gophy")
        XCTAssertTrue(shared.databaseDirectory.path.hasPrefix(expectedBasePath), "Shared instance should use Application Support/Gophy")
        XCTAssertTrue(shared.logsDirectory.path.hasPrefix(expectedBasePath), "Shared instance should use Application Support/Gophy")
    }

    func testDirectoryCreationIdempotent() throws {
        let secondManager = StorageManager(baseDirectory: tempDirectory)

        XCTAssertNoThrow(secondManager.modelsDirectory, "Creating directories should be idempotent")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondManager.modelsDirectory.path), "Directories should still exist")
    }
}
