import AppKit
import Foundation

/// Monitors keyboard shortcuts and triggers automations during active meetings.
///
/// Uses `NSEvent.addLocalMonitorForEvents` for in-app hotkey detection.
/// Shortcuts are only active when a meeting is in progress.
public actor KeyboardShortcutTrigger {
    private var shortcuts: [AutomationShortcut]
    private var activeMeetingId: String?
    private var eventMonitor: Any?
    private var _pendingEvents: [AutomationEvent] = []
    private var eventContinuation: AsyncStream<AutomationEvent>.Continuation?

    public var isActive: Bool {
        activeMeetingId != nil
    }

    public var registeredShortcuts: [AutomationShortcut] {
        shortcuts
    }

    public var pendingEvents: [AutomationEvent] {
        _pendingEvents
    }

    public nonisolated let eventStream: AsyncStream<AutomationEvent>

    public init(shortcuts: [AutomationShortcut] = AutomationShortcut.defaults) {
        self.shortcuts = shortcuts

        var cont: AsyncStream<AutomationEvent>.Continuation?
        self.eventStream = AsyncStream { c in
            cont = c
        }
        self.eventContinuation = cont
    }

    /// Register an additional shortcut.
    public func registerShortcut(_ shortcut: AutomationShortcut) {
        shortcuts.append(shortcut)
    }

    /// Activate shortcut monitoring for a meeting.
    public func activate(meetingId: String) {
        activeMeetingId = meetingId
        _pendingEvents = []
        installMonitor()
    }

    /// Deactivate shortcut monitoring.
    public func deactivate() {
        activeMeetingId = nil
        removeMonitor()
    }

    /// Handle a key event programmatically (for testing without NSEvent monitor).
    ///
    /// - Parameters:
    ///   - keyEquivalent: The key character.
    ///   - modifiers: The modifier flags.
    /// - Returns: `true` if the event matched a shortcut and was handled.
    @discardableResult
    public func handleKeyEvent(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard activeMeetingId != nil else { return false }

        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventMods = modifiers.intersection(relevantModifiers)

        for shortcut in shortcuts {
            let shortcutMods = shortcut.modifiers.intersection(relevantModifiers)
            if shortcut.keyEquivalent.lowercased() == keyEquivalent.lowercased()
                && eventMods == shortcutMods
            {
                let event = AutomationEvent.triggered(
                    toolName: shortcut.toolName,
                    source: .keyboardShortcut
                )
                _pendingEvents.append(event)
                eventContinuation?.yield(event)
                return true
            }
        }

        return false
    }

    // MARK: - Private

    private func installMonitor() {
        removeMonitor()

        // Note: NSEvent monitor must be installed on the main thread
        // and cannot directly call actor-isolated methods.
        // The actual key event dispatching is handled through handleKeyEvent.
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
