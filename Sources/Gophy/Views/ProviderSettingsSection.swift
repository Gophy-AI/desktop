import SwiftUI

@MainActor
struct ProviderSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedProviderConfig: ProviderConfiguration?
    @State private var apiKeyInput: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: TestConnectionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Providers")
                .font(.headline)

            Divider()

            activeProviderSection

            Divider()

            providerListSection
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .sheet(item: $selectedProviderConfig) { config in
            ProviderDetailSheet(
                config: config,
                viewModel: viewModel,
                onDismiss: { selectedProviderConfig = nil }
            )
        }
    }

    // MARK: - Active Provider Pickers

    private var activeProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Provider per Capability")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            capabilityPicker(
                label: "Text Generation",
                capability: .textGeneration
            )

            capabilityPicker(
                label: "Embedding",
                capability: .embedding
            )

            capabilityPicker(
                label: "Speech-to-Text",
                capability: .speechToText
            )

            capabilityPicker(
                label: "Vision / OCR",
                capability: .vision
            )
        }
    }

    private func capabilityPicker(label: String, capability: ProviderCapability) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)

                Spacer()

                Picker("", selection: providerBinding(for: capability)) {
                    Text("Local (On-Device)").tag("local")
                    ForEach(viewModel.configuredProviderConfigs(for: capability), id: \.id) { config in
                        Text(config.name).tag(config.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }

            if viewModel.selectedProviderIdFor(capability) != "local" {
                let providerId = viewModel.selectedProviderIdFor(capability)
                let models = viewModel.availableCloudModels(for: capability, providerId: providerId)
                if !models.isEmpty {
                    HStack {
                        Text("Model")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Picker("", selection: modelBinding(for: capability)) {
                            ForEach(models) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }

    private func providerBinding(for capability: ProviderCapability) -> Binding<String> {
        Binding(
            get: { viewModel.selectedProviderIdFor(capability) },
            set: { newId in
                let models = viewModel.availableCloudModels(for: capability, providerId: newId)
                let defaultModel = models.first?.id ?? ""
                viewModel.selectCloudProvider(for: capability, providerId: newId, modelId: defaultModel)
            }
        )
    }

    private func modelBinding(for capability: ProviderCapability) -> Binding<String> {
        Binding(
            get: { viewModel.selectedModelIdFor(capability) },
            set: { newModelId in
                let providerId = viewModel.selectedProviderIdFor(capability)
                viewModel.selectCloudProvider(for: capability, providerId: providerId, modelId: newModelId)
            }
        )
    }

    // MARK: - Provider List

    private var providerListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Providers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(ProviderCatalog.all) { config in
                ProviderRow(
                    config: config,
                    isConfigured: viewModel.isProviderConfigured(config.id),
                    onTap: { selectedProviderConfig = config }
                )
            }
        }
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let config: ProviderConfiguration
    let isConfigured: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(config.supportedCapabilities.map(\.displayLabel).sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)

                    Text(isConfigured ? "Configured" : "Not Configured")
                        .font(.caption)
                        .foregroundStyle(isConfigured ? .primary : .secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Provider Detail Sheet

@MainActor
private struct ProviderDetailSheet: View {
    let config: ProviderConfiguration
    @Bindable var viewModel: SettingsViewModel
    let onDismiss: () -> Void

    @State private var apiKeyInput: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: TestConnectionResult?
    @State private var showRemoveConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(config.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Supported Capabilities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(Array(config.supportedCapabilities).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                        Text(capability.displayLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("Enter API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        viewModel.saveProviderAPIKey(providerId: config.id, apiKey: apiKeyInput)
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.isEmpty)

                    if viewModel.isProviderConfigured(config.id) {
                        Button("Remove Key") {
                            showRemoveConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }

                    Spacer()

                    if viewModel.isProviderConfigured(config.id) {
                        Button("Test Connection") {
                            isTesting = true
                            testResult = nil
                            Task {
                                testResult = await viewModel.testProviderConnection(providerId: config.id)
                                isTesting = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting)
                    }
                }

                if isTesting {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                }

                if let result = testResult {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(result.isHealthy ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(result.isHealthy ? .primary : .red)
                    }
                }
            }

            if !config.availableModels.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Models")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(config.availableModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Text(model.capability.displayLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let input = model.inputPricePer1MTokens {
                                Text(String(format: "$%.2f/1M in", input))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let output = model.outputPricePer1MTokens {
                                Text(String(format: "$%.2f/1M out", output))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 500, height: 600)
        .alert("Remove API Key", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                viewModel.removeProviderAPIKey(providerId: config.id)
                testResult = nil
            }
        } message: {
            Text("This will remove the API key for \(config.name) and revert any capabilities using this provider to Local.")
        }
    }
}

// MARK: - Test Connection Result

struct TestConnectionResult {
    let isHealthy: Bool
    let message: String
}

// MARK: - ProviderCapability Display

extension ProviderCapability {
    var displayLabel: String {
        switch self {
        case .textGeneration: return "Text Gen"
        case .embedding: return "Embedding"
        case .speechToText: return "STT"
        case .vision: return "Vision"
        }
    }
}
