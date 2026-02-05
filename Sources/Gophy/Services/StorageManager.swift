import Foundation

public final class StorageManager: Sendable {
    public static let shared = StorageManager()

    let baseDirectory: URL

    public let modelsDirectory: URL
    public let databaseDirectory: URL
    public let logsDirectory: URL

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Gophy")

        self.baseDirectory = base
        self.modelsDirectory = base.appendingPathComponent("models")
        self.databaseDirectory = base.appendingPathComponent("data")
        self.logsDirectory = base.appendingPathComponent("logs")

        createDirectories()
    }

    private func createDirectories() {
        let fileManager = FileManager.default
        let directories = [baseDirectory, modelsDirectory, databaseDirectory, logsDirectory]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
}
