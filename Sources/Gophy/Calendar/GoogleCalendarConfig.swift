import Foundation

struct GoogleCalendarConfig: Sendable {
    let clientID: String
    let redirectURI: URL
    let scopes: [String]

    static let defaultScopes = [
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "https://www.googleapis.com/auth/calendar.events"
    ]

    static let keychainItemName = "com.gophy.app.google-auth"

    static let loopbackRedirectURI = URL(string: "http://127.0.0.1")!

    init(
        clientID: String,
        redirectURI: URL = GoogleCalendarConfig.loopbackRedirectURI,
        scopes: [String] = GoogleCalendarConfig.defaultScopes
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}
