import Foundation
import GRDB

public struct SettingRecord: Codable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension SettingRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "settings"
}
