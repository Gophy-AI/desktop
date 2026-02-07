import SwiftUI

/// Settings section for configuring automation behavior.
///
/// Contains master toggle, individual voice/keyboard toggles,
/// pattern list, and confirmation preferences.
@MainActor
struct AutomationSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automations")
                .font(.headline)

            Divider()

            // Master toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Automations", isOn: $viewModel.automationsEnabled)
                    .onChange(of: viewModel.automationsEnabled) { _, newValue in
                        viewModel.updateAutomationsEnabled(newValue)
                    }

                Text("Allow Gophy to execute actions during meetings based on voice commands and keyboard shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.automationsEnabled {
                Divider()

                // Voice commands toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Voice Commands", isOn: $viewModel.voiceCommandsEnabled)
                        .onChange(of: viewModel.voiceCommandsEnabled) { _, newValue in
                            viewModel.updateVoiceCommandsEnabled(newValue)
                        }

                    Text("Detect voice commands like \"remember this\" or \"take a note\" in the transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.voiceCommandsEnabled {
                        voicePatternsList
                    }
                }

                Divider()

                // Keyboard shortcuts toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keyboard Shortcuts", isOn: $viewModel.keyboardShortcutsEnabled)
                        .onChange(of: viewModel.keyboardShortcutsEnabled) { _, newValue in
                            viewModel.updateKeyboardShortcutsEnabled(newValue)
                        }

                    Text("Use keyboard shortcuts to trigger automations during active meetings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.keyboardShortcutsEnabled {
                        shortcutsList
                    }
                }

                Divider()

                // Confirmation preferences
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirmation Preferences")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Tools marked as \"Always allow\" will execute without asking for confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    confirmationToolsList

                    if !viewModel.alwaysAllowedTools.isEmpty {
                        Button("Reset All Confirmations") {
                            viewModel.resetAlwaysAllowed()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var voicePatternsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.voicePatterns, id: \.toolName) { pattern in
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pattern.description)
                        .font(.caption)
                    Spacer()
                    Text(pattern.toolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.leading, 20)
    }

    private var shortcutsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.keyboardShortcuts, id: \.toolName) { shortcut in
                HStack {
                    Image(systemName: "keyboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(shortcut.description)
                        .font(.caption)
                    Spacer()
                    Text(shortcut.toolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.leading, 20)
    }

    private var confirmationToolsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.confirmableTools, id: \.self) { toolName in
                HStack {
                    Text(toolName)
                        .font(.caption)
                    Spacer()
                    if viewModel.alwaysAllowedTools.contains(toolName) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                            Text("Always allowed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Ask each time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, 20)
    }
}
