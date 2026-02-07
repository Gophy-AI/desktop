import SwiftUI
import MLXLMCommon

/// Sheet presented when a tool call requires user confirmation before execution.
///
/// Displays the tool name, description, and arguments. The user can allow or deny,
/// and optionally check "Always allow" to skip future confirmations for this tool.
@MainActor
struct ConfirmationView: View {
    let toolCall: ToolCall
    let onRespond: (Bool, Bool) -> Void

    @State private var alwaysAllow: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Automation Confirmation")
                    .font(.headline)
            }

            Divider()

            // Tool info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tool:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(toolCall.function.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("Arguments:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(formattedArguments)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            // Always allow checkbox
            Toggle("Always allow this action", isOn: $alwaysAllow)
                .font(.caption)

            // Action buttons
            HStack {
                Spacer()

                Button("Deny") {
                    onRespond(false, false)
                }
                .keyboardShortcut(.escape)

                Button("Allow") {
                    onRespond(true, alwaysAllow)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var formattedArguments: String {
        let args = toolCall.function.arguments
        if args.isEmpty {
            return "(no arguments)"
        }

        let lines = args.map { key, value in "\(key): \(value)" }
        return lines.sorted().joined(separator: "\n")
    }
}
