import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MeetingAutoStart")

// MARK: - Protocols

protocol MeetingStarterProtocol: Sendable {
    func startMeeting(title: String, calendarEventId: String?) async throws
    var isRecording: Bool { get async }
}

protocol AutoStartNotifierProtocol: Sendable {
    func notifyAndWait(title: String) async -> AutoStartAction
}

protocol AutoStartSettingsProtocol: Sendable {
    var autoStartEnabled: Bool { get }
    var autoStartOnlyWithVideoLinks: Bool { get }
    var autoStartLeadTimeSeconds: TimeInterval { get }
}

// MARK: - AutoStartAction

enum AutoStartAction: Sendable {
    case startRecording
    case skip
}

// MARK: - UNUserNotification Notifier

final class UserNotificationAutoStartNotifier: AutoStartNotifierProtocol, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func notifyAndWait(title: String) async -> AutoStartAction {
        let content = UNMutableNotificationContent()
        content.title = "Meeting Starting Soon"
        content.body = "'\(title)' is about to begin. Recording will start automatically."
        content.sound = .default
        content.categoryIdentifier = "MEETING_AUTO_START"

        let request = UNNotificationRequest(
            identifier: "autostart-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            logger.warning("Failed to show notification: \(error.localizedDescription, privacy: .public)")
        }

        // Wait 30 seconds for user to dismiss (simplified: always start)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return .startRecording
    }
}

// MARK: - UserDefaults AutoStart Settings

final class UserDefaultsAutoStartSettings: AutoStartSettingsProtocol, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var autoStartEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "calendarAutoStartEnabled"
        if defaults.object(forKey: key) == nil {
            return true
        }
        return defaults.bool(forKey: key)
    }

    var autoStartOnlyWithVideoLinks: Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "calendarAutoStartOnlyVideo"
        if defaults.object(forKey: key) == nil {
            return true
        }
        return defaults.bool(forKey: key)
    }

    var autoStartLeadTimeSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let value = defaults.double(forKey: "calendarAutoStartLeadTime")
        return value > 0 ? value : 60
    }
}

// MARK: - MeetingAutoStartService

actor MeetingAutoStartService {
    private let meetingStarter: any MeetingStarterProtocol
    private let notifier: any AutoStartNotifierProtocol
    private let settings: any AutoStartSettingsProtocol
    private let now: @Sendable () -> Date

    private var scheduledEventIds: Set<String> = []
    private var pendingTasks: [String: Task<Void, Never>] = [:]

    init(
        meetingStarter: any MeetingStarterProtocol,
        notifier: any AutoStartNotifierProtocol,
        settings: any AutoStartSettingsProtocol = UserDefaultsAutoStartSettings(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.meetingStarter = meetingStarter
        self.notifier = notifier
        self.settings = settings
        self.now = now
    }

    func evaluateEvents(_ events: [UnifiedCalendarEvent]) {
        guard settings.autoStartEnabled else {
            cancelAllPending()
            return
        }

        let currentDate = now()
        let leadTime = settings.autoStartLeadTimeSeconds

        // Cancel tasks for events that are no longer relevant
        let currentEventIds = Set(events.map { $0.id })
        for (id, task) in pendingTasks where !currentEventIds.contains(id) {
            task.cancel()
            pendingTasks.removeValue(forKey: id)
            scheduledEventIds.remove(id)
        }

        for event in events {
            guard !scheduledEventIds.contains(event.id) else { continue }
            guard event.endDate > currentDate else { continue }

            if settings.autoStartOnlyWithVideoLinks && event.meetingLink == nil {
                continue
            }

            let triggerTime = event.startDate.addingTimeInterval(-leadTime)
            let delay = triggerTime.timeIntervalSince(currentDate)

            if delay <= 0 && event.startDate.timeIntervalSince(currentDate) > -300 {
                // Should trigger now (within window)
                scheduledEventIds.insert(event.id)
                let eventCopy = event
                pendingTasks[event.id] = Task {
                    await self.triggerAutoStart(for: eventCopy)
                }
            } else if delay > 0 {
                // Schedule for future
                scheduledEventIds.insert(event.id)
                let eventCopy = event
                let delayNanos = UInt64(delay * 1_000_000_000)
                pendingTasks[event.id] = Task {
                    do {
                        try await Task.sleep(nanoseconds: delayNanos)
                        guard !Task.isCancelled else { return }
                        await self.triggerAutoStart(for: eventCopy)
                    } catch {
                        // Task was cancelled
                    }
                }
            }
        }
    }

    func cancelAll() {
        cancelAllPending()
    }

    // MARK: - Private

    private func triggerAutoStart(for event: UnifiedCalendarEvent) async {
        guard settings.autoStartEnabled else { return }

        let isCurrentlyRecording = await meetingStarter.isRecording
        guard !isCurrentlyRecording else {
            logger.info("Skipping auto-start for '\(event.title, privacy: .public)': already recording")
            return
        }

        logger.info("Auto-start: notifying for '\(event.title, privacy: .public)'")
        let action = await notifier.notifyAndWait(title: event.title)

        switch action {
        case .startRecording:
            do {
                try await meetingStarter.startMeeting(
                    title: event.title,
                    calendarEventId: event.googleEventId
                )
                logger.info("Auto-start: recording started for '\(event.title, privacy: .public)'")
            } catch {
                logger.error("Auto-start: failed to start recording: \(error.localizedDescription, privacy: .public)")
            }

        case .skip:
            logger.info("Auto-start: user skipped '\(event.title, privacy: .public)'")
        }

        pendingTasks.removeValue(forKey: event.id)
    }

    private func cancelAllPending() {
        for (_, task) in pendingTasks {
            task.cancel()
        }
        pendingTasks.removeAll()
        scheduledEventIds.removeAll()
    }
}
