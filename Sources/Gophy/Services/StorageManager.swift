import Foundation

public final class StorageManager: Sendable {
    public static let shared = StorageManager()

    let baseDirectory: URL

    public let modelsDirectory: URL
    public let databaseDirectory: URL
    public let logsDirectory: URL
    public let recordingsDirectory: URL

    /// Alternative models directory (for checking both sandbox and non-sandbox paths)
    public let alternativeModelsDirectory: URL?

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Gophy")

        self.baseDirectory = base
        self.modelsDirectory = base.appendingPathComponent("models")
        self.databaseDirectory = base.appendingPathComponent("data")
        self.logsDirectory = base.appendingPathComponent("logs")
        self.recordingsDirectory = base.appendingPathComponent("recordings")

        // Check if we're in sandbox (Containers path) or not
        // If in sandbox, also check non-sandbox path for existing models
        // If not in sandbox, also check sandbox path for existing models
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.gophy.app/Data/Library/Application Support/Gophy/models")
        let regularPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Gophy/models")

        // Set alternative path to whichever one we're NOT using as primary
        if base.path.contains("Containers/com.gophy.app") {
            // We're sandboxed, check regular path as alternative
            self.alternativeModelsDirectory = regularPath
        } else {
            // We're not sandboxed, check container path as alternative
            self.alternativeModelsDirectory = containerPath
        }

        createDirectories()
    }

    private func createDirectories() {
        let fileManager = FileManager.default
        let directories = [baseDirectory, modelsDirectory, databaseDirectory, logsDirectory, recordingsDirectory]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
}
