import SwiftUI

@MainActor
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel(
        audioDeviceManager: AudioDeviceManager(),
        storageManager: .shared,
        registry: .shared
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                languageSection
                ProviderSettingsSection(viewModel: viewModel)
                CalendarSettingsSection(viewModel: viewModel)
                AutomationSettingsView(viewModel: viewModel)
                audioSection
                modelsSection
                storageSection
                generalSection
            }
            .padding()
        }
        .navigationTitle("Settings")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear All Data", isPresented: $viewModel.showClearDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Data", role: .destructive) {
                Task {
                    await viewModel.clearAllData()
                }
            }
        } message: {
            Text("This will permanently delete all meetings, transcripts, documents, and chat history. This action cannot be undone.")
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Language", selection: $viewModel.languagePreference) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.languagePreference) { _, newValue in
                    viewModel.updateLanguagePreference(newValue)
                }

                Text("When set to Auto-detect, Gophy detects the spoken language automatically. Force a language for better accuracy in single-language meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Input Device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Input Device", selection: $viewModel.selectedDevice) {
                    Text("None").tag(nil as AudioDevice?)
                    ForEach(viewModel.availableInputDevices) { device in
                        Text("\(device.name) (\(Int(device.sampleRate)) Hz)")
                            .tag(device as AudioDevice?)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedDevice) { _, newDevice in
                    if let device = newDevice {
                        viewModel.selectInputDevice(device)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable System Audio Capture", isOn: $viewModel.systemAudioEnabled)
                    .onChange(of: viewModel.systemAudioEnabled) { _, _ in
                        viewModel.toggleSystemAudio()
                    }

                Text("Capture audio from apps and system sounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("VAD Sensitivity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.2f", viewModel.vadSensitivity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $viewModel.vadSensitivity, in: 0.0...1.0)
                    .onChange(of: viewModel.vadSensitivity) { _, newValue in
                        viewModel.updateVADSensitivity(newValue)
                    }

                Text("Higher values are more sensitive to voice detection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Text Generation Model", selection: $viewModel.selectedTextGenModelId) {
                    ForEach(viewModel.availableTextGenModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedTextGenModelId) { _, newValue in
                    viewModel.updateSelectedTextGenModel(newValue)
                }

                Text("Qwen3 supports 119 languages (vs 29 for Qwen2.5) and improved benchmarks. Requires ~4.5 GB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Storage")
                        .font(.subheadline)

                    Text(String(format: "%.2f GB used", viewModel.totalModelStorageGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink(value: SidebarItem.models) {
                    Text("Manage Models")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Database Location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open in Finder") {
                        viewModel.openDatabaseInFinder()
                    }
                    .buttonStyle(.bordered)
                }

                Text(viewModel.databaseLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Database Storage")
                        .font(.subheadline)

                    Spacer()

                    Text(String(format: "%.2f GB", viewModel.totalStorageGB))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("Clear All Data") {
                    viewModel.confirmClearData()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Auto-Suggest Interval")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(viewModel.autoSuggestInterval))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $viewModel.autoSuggestInterval, in: 10.0...120.0, step: 5.0)
                    .onChange(of: viewModel.autoSuggestInterval) { _, newValue in
                        viewModel.updateAutoSuggestInterval(newValue)
                    }

                Text("How often to generate automatic suggestions during meetings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
