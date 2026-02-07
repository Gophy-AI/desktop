import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "GoogleCalendarAPI")

// MARK: - Protocol for Auth Service

protocol GoogleAuthServiceProtocol: Sendable {
    func freshAccessToken() async throws -> String
}

extension GoogleAuthService: GoogleAuthServiceProtocol {}

// MARK: - Error Types

enum CalendarAPIError: Error, LocalizedError, Sendable {
    case syncTokenExpired
    case rateLimited
    case unauthorized
    case serverError(Int, String)
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .syncTokenExpired:
            return "Calendar sync token expired. A full re-sync is needed."
        case .rateLimited:
            return "Google Calendar API rate limit exceeded. Please try again later."
        case .unauthorized:
            return "Not authorized to access Google Calendar. Please sign in again."
        case .serverError(let code, let message):
            return "Google Calendar API error (\(code)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to parse calendar data: \(message)"
        }
    }
}

// MARK: - Protocol for API Client

protocol GoogleCalendarAPIClientProtocol: Sendable {
    func fetchCalendarList() async throws -> [CalendarInfo]
    func fetchEvents(
        calendarId: String,
        timeMin: Date?,
        timeMax: Date?,
        syncToken: String?,
        pageToken: String?
    ) async throws -> EventListResponse
    func patchEvent(calendarId: String, eventId: String, description: String) async throws
    func patchExtendedProperties(calendarId: String, eventId: String, properties: [String: String]) async throws
}

// MARK: - GoogleCalendarAPIClient

actor GoogleCalendarAPIClient: GoogleCalendarAPIClientProtocol {
    private let authService: any GoogleAuthServiceProtocol
    private let session: URLSession
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    private let maxRetries = 3

    init(
        authService: any GoogleAuthServiceProtocol,
        session: URLSession = .shared
    ) {
        self.authService = authService
        self.session = session
    }

    // MARK: - Calendar List

    func fetchCalendarList() async throws -> [CalendarInfo] {
        let url = URL(string: "\(baseURL)/users/me/calendarList")!
        let data = try await performAuthorizedRequest(url: url, method: "GET")
        let response = try decode(CalendarListResponse.self, from: data)
        return response.items
    }

    // MARK: - Events

    func fetchEvents(
        calendarId: String,
        timeMin: Date? = nil,
        timeMax: Date? = nil,
        syncToken: String? = nil,
        pageToken: String? = nil
    ) async throws -> EventListResponse {
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedCalendarId)/events")!

        var queryItems: [URLQueryItem] = []

        if let syncToken = syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            queryItems.append(URLQueryItem(name: "singleEvents", value: "true"))
            queryItems.append(URLQueryItem(name: "orderBy", value: "startTime"))

            if let timeMin = timeMin {
                queryItems.append(URLQueryItem(name: "timeMin", value: iso8601String(from: timeMin)))
            }
            if let timeMax = timeMax {
                queryItems.append(URLQueryItem(name: "timeMax", value: iso8601String(from: timeMax)))
            }
        }

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems

        let data = try await performAuthorizedRequest(url: components.url!, method: "GET")
        return try decode(EventListResponse.self, from: data)
    }

    // MARK: - Patch

    func patchEvent(
        calendarId: String,
        eventId: String,
        description: String
    ) async throws {
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        let body: [String: Any] = ["description": description]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        _ = try await performAuthorizedRequest(url: url, method: "PATCH", body: bodyData)
    }

    func patchExtendedProperties(
        calendarId: String,
        eventId: String,
        properties: [String: String]
    ) async throws {
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "\(baseURL)/calendars/\(encodedCalendarId)/events/\(encodedEventId)")!

        let body: [String: Any] = [
            "extendedProperties": [
                "private": properties
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        _ = try await performAuthorizedRequest(url: url, method: "PATCH", body: bodyData)
    }

    // MARK: - Request Execution

    private func performAuthorizedRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        retryCount: Int = 0,
        isRetryAfterAuth: Bool = false
    ) async throws -> Data {
        let accessToken = try await authService.freshAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = body
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CalendarAPIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarAPIError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data

        case 401:
            if !isRetryAfterAuth {
                logger.info("Received 401, refreshing token and retrying")
                return try await performAuthorizedRequest(
                    url: url,
                    method: method,
                    body: body,
                    retryCount: retryCount,
                    isRetryAfterAuth: true
                )
            }
            throw CalendarAPIError.unauthorized

        case 410:
            logger.info("Received 410 GONE - sync token expired")
            throw CalendarAPIError.syncTokenExpired

        case 429:
            if retryCount < maxRetries {
                let delay = pow(2.0, Double(retryCount))
                logger.info("Rate limited, retrying after \(delay, privacy: .public)s (attempt \(retryCount + 1, privacy: .public))")
                try await Task.sleep(nanoseconds: UInt64(delay * 100_000_000))
                return try await performAuthorizedRequest(
                    url: url,
                    method: method,
                    body: body,
                    retryCount: retryCount + 1,
                    isRetryAfterAuth: isRetryAfterAuth
                )
            }
            throw CalendarAPIError.rateLimited

        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CalendarAPIError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw CalendarAPIError.decodingError(error.localizedDescription)
        }
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
