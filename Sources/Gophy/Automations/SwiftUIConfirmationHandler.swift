import Foundation
import MLXLMCommon
import Observation
import SwiftUI

/// SwiftUI-based confirmation handler that presents a sheet for user approval.
///
/// Uses `withCheckedContinuation` to bridge the SwiftUI sheet presentation
/// to the async `confirm(toolCall:)` method expected by the pipeline.
@MainActor
@Observable
public final class SwiftUIConfirmationHandler: ConfirmationHandler, @unchecked Sendable {
    /// State controlling the confirmation sheet.
    public var pendingToolCall: ToolCall?
    public var isPresented: Bool = false

    /// Tool names the user has marked as "Always allow".
    public var alwaysAllowed: Set<String> = []

    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {
        loadAlwaysAllowed()
    }

    public func confirm(toolCall: ToolCall) async -> Bool {
        let name = toolCall.function.name

        // Check if user previously chose "Always allow"
        if alwaysAllowed.contains(name) {
            return true
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingToolCall = toolCall
            self.isPresented = true
        }
    }

    /// Called from the confirmation view when the user makes a decision.
    public func respond(approved: Bool, alwaysAllow: Bool) {
        if approved && alwaysAllow, let name = pendingToolCall?.function.name {
            alwaysAllowed.insert(name)
            saveAlwaysAllowed()
        }

        pendingToolCall = nil
        isPresented = false
        continuation?.resume(returning: approved)
        continuation = nil
    }

    /// Remove a tool from the "Always allow" set.
    public func revokeAlwaysAllow(for toolName: String) {
        alwaysAllowed.remove(toolName)
        saveAlwaysAllowed()
    }

    /// Reset all "Always allow" preferences.
    public func resetAlwaysAllowed() {
        alwaysAllowed.removeAll()
        saveAlwaysAllowed()
    }

    // MARK: - Persistence

    private func loadAlwaysAllowed() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "automations.alwaysAllowedTools") {
            alwaysAllowed = Set(saved)
        }
    }

    private func saveAlwaysAllowed() {
        let defaults = UserDefaults.standard
        defaults.set(Array(alwaysAllowed), forKey: "automations.alwaysAllowedTools")
    }
}
