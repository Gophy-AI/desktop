import XCTest
@testable import Gophy

final class GoogleCalendarAPIClientTests: XCTestCase {

    // MARK: - Mock Auth Service

    actor MockGoogleAuthForAPI: GoogleAuthServiceProtocol {
        var tokenToReturn = "mock-bearer-token"
        private(set) var tokenRequestCount = 0
        private(set) var isSignedIn = true

        func freshAccessToken() async throws -> String {
            tokenRequestCount += 1
            guard isSignedIn else {
                throw GoogleAuthError.notSignedIn
            }
            return tokenToReturn
        }

        func setToken(_ token: String) {
            tokenToReturn = token
        }

        func setSignedOut() {
            isSignedIn = false
        }
    }

    // MARK: - Mock URL Protocol

    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocolDidFinishLoading(self)
                return
            }

            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    // MARK: - Helpers

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream = stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - Setup

    private var mockAuth: MockGoogleAuthForAPI!
    private var client: GoogleCalendarAPIClient!
    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        mockAuth = MockGoogleAuthForAPI()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        client = GoogleCalendarAPIClient(
            authService: mockAuth,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Calendar List Tests

    func testFetchCalendarListReturnsParsedCalendars() async throws {
        let json = """
        {
            "items": [
                {
                    "id": "primary",
                    "summary": "My Calendar",
                    "primary": true,
                    "backgroundColor": "#4285f4"
                },
                {
                    "id": "work@example.com",
                    "summary": "Work",
                    "primary": false,
                    "backgroundColor": "#0b8043"
                }
            ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/calendar/v3/users/me/calendarList")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-bearer-token")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json.data(using: .utf8)!, response)
        }

        let calendars = try await client.fetchCalendarList()

        XCTAssertEqual(calendars.count, 2)
        XCTAssertEqual(calendars[0].id, "primary")
        XCTAssertEqual(calendars[0].summary, "My Calendar")
        XCTAssertEqual(calendars[0].primary, true)
        XCTAssertEqual(calendars[1].id, "work@example.com")
        XCTAssertEqual(calendars[1].summary, "Work")
    }

    // MARK: - Events Tests

    func testFetchEventsReturnsParsedEventsWithFields() async throws {
        let json = """
        {
            "items": [
                {
                    "id": "event1",
                    "summary": "Team Standup",
                    "description": "Daily sync",
                    "start": {"dateTime": "2026-02-07T10:00:00Z"},
                    "end": {"dateTime": "2026-02-07T10:30:00Z"},
                    "location": "Room A",
                    "status": "confirmed",
                    "attendees": [
                        {
                            "email": "alice@example.com",
                            "displayName": "Alice",
                            "responseStatus": "accepted",
                            "self": true
                        }
                    ],
                    "conferenceData": {
                        "entryPoints": [
                            {
                                "uri": "https://meet.google.com/abc-defg-hij",
                                "label": "meet.google.com/abc-defg-hij",
                                "entryPointType": "video"
                            }
                        ]
                    },
                    "htmlLink": "https://calendar.google.com/event?id=event1",
                    "organizer": {
                        "email": "bob@example.com",
                        "displayName": "Bob"
                    }
                }
            ],
            "nextSyncToken": "sync-token-123"
        }
        """

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            XCTAssertTrue(url.path.contains("/calendar/v3/calendars/"))
            XCTAssertTrue(url.path.contains("/events"))

            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let params = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
            XCTAssertEqual(params["singleEvents"], "true")
            XCTAssertEqual(params["orderBy"], "startTime")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json.data(using: .utf8)!, response)
        }

        let result = try await client.fetchEvents(
            calendarId: "primary",
            timeMin: Date(),
            timeMax: Date().addingTimeInterval(86400)
        )

        XCTAssertEqual(result.events.count, 1)
        let event = result.events[0]
        XCTAssertEqual(event.id, "event1")
        XCTAssertEqual(event.summary, "Team Standup")
        XCTAssertEqual(event.description, "Daily sync")
        XCTAssertEqual(event.location, "Room A")
        XCTAssertEqual(event.status, "confirmed")
        XCTAssertEqual(event.attendees?.count, 1)
        XCTAssertEqual(event.attendees?[0].email, "alice@example.com")
        XCTAssertEqual(event.attendees?[0].isSelf, true)
        XCTAssertEqual(event.meetingLink, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(event.organizer?.displayName, "Bob")
        XCTAssertEqual(result.nextSyncToken, "sync-token-123")
    }

    func testFetchEventsWithSyncTokenReturnsOnlyChangedEvents() async throws {
        let json = """
        {
            "items": [
                {
                    "id": "changed-event",
                    "summary": "Updated Meeting",
                    "start": {"dateTime": "2026-02-07T14:00:00Z"},
                    "end": {"dateTime": "2026-02-07T15:00:00Z"}
                }
            ],
            "nextSyncToken": "new-sync-token"
        }
        """

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let params = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
            XCTAssertEqual(params["syncToken"], "old-sync-token")
            XCTAssertNil(params["timeMin"])
            XCTAssertNil(params["timeMax"])

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json.data(using: .utf8)!, response)
        }

        let result = try await client.fetchEvents(
            calendarId: "primary",
            syncToken: "old-sync-token"
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].id, "changed-event")
        XCTAssertEqual(result.nextSyncToken, "new-sync-token")
    }

    // MARK: - Patch Tests

    func testPatchEventDescriptionUpdatesDescription() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url!.path.contains("/calendar/v3/calendars/primary/events/event1"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let bodyData = request.httpBody ?? Self.readStream(request.httpBodyStream)
            if let bodyData = bodyData {
                let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
                XCTAssertEqual(body["description"] as? String, "Updated description")
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return ("{}".data(using: .utf8)!, response)
        }

        try await client.patchEvent(
            calendarId: "primary",
            eventId: "event1",
            description: "Updated description"
        )
    }

    func testPatchExtendedPropertiesStoresPrivateProperties() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")

            let bodyData = request.httpBody ?? Self.readStream(request.httpBodyStream)
            if let bodyData = bodyData {
                let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
                let extendedProps = body["extendedProperties"] as! [String: Any]
                let privateProps = extendedProps["private"] as! [String: String]
                XCTAssertEqual(privateProps["gophy_summary"], "Meeting notes here")
                XCTAssertEqual(privateProps["gophy_meeting_id"], "meeting-123")
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return ("{}".data(using: .utf8)!, response)
        }

        try await client.patchExtendedProperties(
            calendarId: "primary",
            eventId: "event1",
            properties: [
                "gophy_summary": "Meeting notes here",
                "gophy_meeting_id": "meeting-123"
            ]
        )
    }

    // MARK: - Error Handling Tests

    func testUnauthorizedResponseTriggersTokenRefreshAndRetry() async throws {
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1

            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return ("{\"error\": {\"code\": 401}}".data(using: .utf8)!, response)
            }

            let json = """
            {
                "items": [
                    {"id": "cal1", "summary": "Calendar", "primary": true}
                ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json.data(using: .utf8)!, response)
        }

        let calendars = try await client.fetchCalendarList()
        XCTAssertEqual(calendars.count, 1)
        XCTAssertEqual(requestCount, 2)
    }

    func testGoneResponseOnSyncTokenThrowsSyncTokenExpired() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 410,
                httpVersion: nil,
                headerFields: nil
            )!
            return ("{\"error\": {\"code\": 410}}".data(using: .utf8)!, response)
        }

        do {
            _ = try await client.fetchEvents(
                calendarId: "primary",
                syncToken: "stale-token"
            )
            XCTFail("Expected SyncTokenExpired error")
        } catch let error as CalendarAPIError {
            if case .syncTokenExpired = error {
                // Expected
            } else {
                XCTFail("Expected syncTokenExpired, got \(error)")
            }
        }
    }

    func testRateLimitResponseTriggersRetryWithBackoff() async throws {
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1

            if requestCount <= 2 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return ("{\"error\": {\"code\": 429}}".data(using: .utf8)!, response)
            }

            let json = """
            {"items": [{"id": "cal1", "summary": "Calendar"}]}
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (json.data(using: .utf8)!, response)
        }

        let calendars = try await client.fetchCalendarList()
        XCTAssertEqual(calendars.count, 1)
        XCTAssertEqual(requestCount, 3)
    }

    func testRateLimitExhaustsRetriesThrowsError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return ("{\"error\": {\"code\": 429}}".data(using: .utf8)!, response)
        }

        do {
            _ = try await client.fetchCalendarList()
            XCTFail("Expected rateLimited error")
        } catch let error as CalendarAPIError {
            if case .rateLimited = error {
                // Expected
            } else {
                XCTFail("Expected rateLimited, got \(error)")
            }
        }
    }
}
