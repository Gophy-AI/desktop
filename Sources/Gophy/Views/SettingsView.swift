import SwiftUI

@MainActor
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel(
        audioDeviceManager: AudioDeviceManager(),
        storageManager: .shared,
        registry: ModelRegistry.shared
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
                inferenceSection
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

            // STT Model Picker
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isCloudProvider(for: .speechToText) {
                    HStack {
                        Text("Speech-to-Text Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Using cloud: \(viewModel.selectedProviderIdFor(.speechToText))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Picker("Speech-to-Text Model", selection: $viewModel.selectedSTTModelId) {
                        ForEach(viewModel.availableSTTModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedSTTModelId) { _, newValue in
                        viewModel.updateSelectedSTTModel(newValue)
                    }
                }
            }

            Divider()

            // Text Generation Model Picker
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isCloudProvider(for: .textGeneration) {
                    HStack {
                        Text("Text Generation Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Using cloud: \(viewModel.selectedProviderIdFor(.textGeneration))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else {
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
            }

            Divider()

            // OCR/Vision Model Picker
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isCloudProvider(for: .vision) {
                    HStack {
                        Text("OCR/Vision Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Using cloud: \(viewModel.selectedProviderIdFor(.vision))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Picker("OCR/Vision Model", selection: $viewModel.selectedOCRModelId) {
                        ForEach(viewModel.availableOCRModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedOCRModelId) { _, newValue in
                        viewModel.updateSelectedOCRModel(newValue)
                    }
                }
            }

            Divider()

            // Embedding Model Picker
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isCloudProvider(for: .embedding) {
                    HStack {
                        Text("Embedding Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Using cloud: \(viewModel.selectedProviderIdFor(.embedding))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Picker("Embedding Model", selection: $viewModel.selectedEmbeddingModelId) {
                        ForEach(viewModel.availableEmbeddingModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedEmbeddingModelId) { _, newValue in
                        viewModel.updateSelectedEmbeddingModel(newValue)
                    }
                }
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

    private var inferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inference")
                .font(.headline)

            Divider()

            // Max Tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Max Tokens (Chat)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(viewModel.inferenceMaxTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $viewModel.inferenceMaxTokens, in: 256...8192, step: 256)
                    .onChange(of: viewModel.inferenceMaxTokens) { _, newValue in
                        viewModel.updateInferenceMaxTokens(newValue)
                    }

                Text("Maximum number of tokens the model generates for chat and suggestion responses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Temperature
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.2f", viewModel.inferenceTemperature))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $viewModel.inferenceTemperature, in: 0.0...2.0, step: 0.05)
                    .onChange(of: viewModel.inferenceTemperature) { _, newValue in
                        viewModel.updateInferenceTemperature(newValue)
                    }

                Text("Lower values produce more focused responses, higher values more creative")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Thinking toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Thinking (Qwen3)", isOn: $viewModel.thinkingEnabled)
                    .onChange(of: viewModel.thinkingEnabled) { _, newValue in
                        viewModel.updateThinkingEnabled(newValue)
                    }

                Text("When enabled, Qwen3 models show their reasoning process in a collapsible bubble. Disable to skip thinking and get faster, shorter responses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // OCR Max Tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Max Tokens (OCR)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(viewModel.ocrMaxTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $viewModel.ocrMaxTokens, in: 1024...16384, step: 1024)
                    .onChange(of: viewModel.ocrMaxTokens) { _, newValue in
                        viewModel.updateOCRMaxTokens(newValue)
                    }

                Text("Maximum tokens for OCR text extraction from images and documents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
