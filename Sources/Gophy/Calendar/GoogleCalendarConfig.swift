import Foundation

struct GoogleCalendarConfig: Sendable {
    static let clientID: String = {
        guard let value = Bundle.main.infoDictionary?["GoogleClientID"] as? String, !value.isEmpty else {
            return ""
        }
        return value
    }()

    static let clientSecret: String = {
        guard let value = Bundle.main.infoDictionary?["GoogleClientSecret"] as? String, !value.isEmpty else {
            return ""
        }
        return value
    }()

    let scopes: [String]

    static let defaultScopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events"
    ]

    static let keychainItemName = "com.gophy.app.google-auth"

    static let loopbackRedirectURI = URL(string: "http://127.0.0.1")!

    var isConfigured: Bool {
        !GoogleCalendarConfig.clientID.isEmpty
    }

    init(scopes: [String] = GoogleCalendarConfig.defaultScopes) {
        self.scopes = scopes
    }
}
