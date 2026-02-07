@preconcurrency import Foundation
import EventKit
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "EventKit")

// MARK: - Errors

enum EventKitError: Error, LocalizedError, Sendable {
    case accessDenied
    case accessRestricted
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Please grant access in System Settings > Privacy > Calendars."
        case .accessRestricted:
            return "Calendar access is restricted by system policy."
        case .unknown(let message):
            return "Calendar error: \(message)"
        }
    }
}

// MARK: - Protocol

protocol EventKitServiceProtocol: Sendable {
    func requestAccess() async throws -> Bool
    func fetchCalendars() -> [LocalCalendar]
    func fetchUpcomingEvents(from: Date, to: Date, calendars: [String]?) -> [LocalCalendarEvent]
    func observe() -> AsyncStream<Void>
}

// MARK: - EventKitService

final class EventKitService: EventKitServiceProtocol, @unchecked Sendable {
    private let store: EKEventStore
    private let lock = NSLock()

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized, .fullAccess:
            return true

        case .denied:
            throw EventKitError.accessDenied

        case .restricted:
            throw EventKitError.accessRestricted

        case .notDetermined, .writeOnly:
            let granted = try await store.requestFullAccessToEvents()
            if !granted {
                throw EventKitError.accessDenied
            }
            return granted

        @unknown default:
            let granted = try await store.requestFullAccessToEvents()
            if !granted {
                throw EventKitError.accessDenied
            }
            return granted
        }
    }

    func fetchCalendars() -> [LocalCalendar] {
        let ekCalendars = store.calendars(for: .event)
        return ekCalendars.map { calendar in
            LocalCalendar(
                identifier: calendar.calendarIdentifier,
                title: calendar.title,
                type: mapCalendarType(calendar.type),
                source: calendar.source?.title ?? "Unknown",
                color: hexString(from: calendar.cgColor)
            )
        }
    }

    func fetchUpcomingEvents(from startDate: Date, to endDate: Date, calendars: [String]?) -> [LocalCalendarEvent] {
        var ekCalendars: [EKCalendar]?

        if let calendarIds = calendars {
            ekCalendars = calendarIds.compactMap { id in
                store.calendar(withIdentifier: id)
            }
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: ekCalendars)
        let ekEvents = store.events(matching: predicate)

        return ekEvents
            .map { event in
                LocalCalendarEvent(
                    identifier: event.eventIdentifier,
                    title: event.title ?? "",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    location: event.location,
                    notes: event.notes,
                    calendarTitle: event.calendar.title,
                    isAllDay: event.isAllDay,
                    url: event.url,
                    organizer: event.organizer?.name
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func observe() -> AsyncStream<Void> {
        let eventStore = store
        return AsyncStream { continuation in
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: eventStore,
                queue: nil
            ) { _ in
                continuation.yield()
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Private Helpers

    private func mapCalendarType(_ type: EKCalendarType) -> LocalCalendarType {
        switch type {
        case .local:
            return .local
        case .calDAV:
            return .calDAV
        case .exchange:
            return .exchange
        case .birthday:
            return .birthday
        case .subscription:
            return .local
        @unknown default:
            return .local
        }
    }

    private func hexString(from cgColor: CGColor?) -> String {
        guard let color = cgColor,
              let components = color.components,
              components.count >= 3 else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
