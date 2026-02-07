import SwiftUI

/// A compact status bar showing automation state during meetings.
///
/// Displays the master toggle, last automation result, and an undo button.
@MainActor
struct AutomationStatusBar: View {
    let isEnabled: Bool
    let lastEvent: AutomationEvent?
    let canUndo: Bool
    let onToggle: (Bool) -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Toggle
            Toggle("Automations", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            // Last event indicator
            if let event = lastEvent {
                lastEventView(event)
            }

            // Undo button
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
            }
            .disabled(!canUndo)
            .help("Undo last automation action")
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func lastEventView(_ event: AutomationEvent) -> some View {
        switch event {
        case .completed(let toolName, let result):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(toolName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(result.prefix(40) + (result.count > 40 ? "..." : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        case .executing(let toolName):
            HStack(spacing: 4) {
                SwiftUI.ProgressView()
                    .controlSize(.mini)
                Text(toolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed(let toolName, let error):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(toolName)
                    .font(.caption)
                Text(error.prefix(30))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .triggered(let toolName, _):
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(toolName)
                    .font(.caption)
            }

        case .confirmationNeeded:
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("Awaiting confirmation")
                    .font(.caption)
            }
        }
    }
}
