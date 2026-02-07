import SwiftUI
import AVFoundation

@MainActor
struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel(
        modelManagerViewModel: ModelManagerViewModel()
    )
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)

            navigationBar
        }
        .frame(width: 600, height: 580)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeStep(onNext: { viewModel.nextStep() })
        case .permissions:
            PermissionsStep(viewModel: viewModel)
        case .language:
            LanguageStep(viewModel: viewModel)
        case .calendar:
            CalendarOnboardingStep(viewModel: viewModel)
        case .models:
            ModelsStep(viewModel: viewModel)
        case .cloudProviders:
            CloudProvidersOnboardingStep()
        case .done:
            DoneStep(onComplete: {
                viewModel.completeOnboarding()
                onComplete()
            })
        }
    }

    private var navigationBar: some View {
        HStack {
            if viewModel.currentStep.rawValue > 0 && viewModel.currentStep != .done {
                Button("Back") {
                    viewModel.previousStep()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(OnboardingViewModel.OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue == viewModel.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            if viewModel.currentStep != .done {
                Button("Next") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceed(from: viewModel.currentStep))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 120, height: 120)

            Text("Welcome to Gophy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your AI-powered call assistant")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "mic.fill", title: "Real-time Transcription", description: "Capture every word with accurate speech-to-text")
                FeatureRow(icon: "lightbulb.fill", title: "Contextual Suggestions", description: "Get AI-powered insights during meetings")
                FeatureRow(icon: "doc.text.fill", title: "Document RAG", description: "Search and reference your documents")
            }
            .padding(.top, 24)

            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionsStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(permissionColor)

            Text("Microphone Access")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Gophy needs access to your microphone to transcribe meetings")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                HStack {
                    Text("Status:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(permissionColor)
                            .frame(width: 8, height: 8)

                        Text(permissionStatusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                if viewModel.microphonePermissionStatus == .notDetermined {
                    Button("Grant Microphone Access") {
                        Task {
                            await viewModel.requestMicrophonePermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCheckingPermissions)
                } else if viewModel.microphonePermissionStatus == .denied {
                    VStack(spacing: 12) {
                        Text("Microphone access was denied")
                            .font(.subheadline)
                            .foregroundStyle(.red)

                        Button("Open System Preferences") {
                            viewModel.openSystemPreferences()
                        }
                        .buttonStyle(.bordered)

                        Button("Check Again") {
                            viewModel.checkPermissions()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Spacer()
        }
    }

    private var permissionColor: Color {
        switch viewModel.microphonePermissionStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var permissionStatusText: String {
        switch viewModel.microphonePermissionStatus {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }
}

struct LanguageStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Select Your Language")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Choose your primary language for transcription and suggestions")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Language", selection: $viewModel.languagePreference) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: viewModel.languagePreference) { _, newValue in
                viewModel.updateLanguagePreference(newValue)
            }

            Text("When set to Auto-detect, Gophy detects the spoken language automatically. Force a language for better accuracy in single-language meetings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
    }
}

struct ModelsStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Download Models")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Download at least one model to enable Gophy's features")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.hasDownloadedModels {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)

                    Text("Download the Speech-to-Text model to get started with transcription")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.models) { model in
                        OnboardingModelRow(
                            model: model,
                            isDownloaded: viewModel.isDownloaded(model),
                            isDownloading: viewModel.isDownloading(model),
                            progress: viewModel.downloadProgress(for: model),
                            onDownload: { viewModel.downloadModel(model) },
                            onCancel: { viewModel.cancelDownload(model) }
                        )
                    }
                }
            }
            .frame(maxHeight: 250)

            if viewModel.totalModelDiskUsage > 0 {
                HStack {
                    Text("Total disk usage:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.2f GB", viewModel.totalModelDiskUsage))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }
}

struct OnboardingModelRow: View {
    let model: ModelDefinition
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: DownloadProgress?
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)

                    Text("\(model.type.displayName) • \(String(format: "%.1f GB", model.approximateSizeGB))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloading {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if isDownloaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Download") {
                        onDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let progress = progress, isDownloading {
                SwiftUI.ProgressView(value: progress.fractionCompleted) {
                    Text(String(format: "%.0f%%", progress.fractionCompleted * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct CalendarOnboardingStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Connect Your Calendar")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Optionally connect calendars to see upcoming meetings, auto-start recordings, and write summaries back to events")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.eventKitGranted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text("Local Calendars (EventKit)")
                        .font(.subheadline)

                    Spacer()

                    if viewModel.eventKitGranted {
                        Text("Granted")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            Task {
                                await viewModel.requestEventKitAccess()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)

                    Text("Google Calendar can be connected later in Settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .frame(maxWidth: 400)

            Button("Skip for Now") {
                viewModel.skipCalendarSetup()
                viewModel.nextStep()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

struct CloudProvidersOnboardingStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Cloud AI Providers")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Optionally use cloud AI providers like OpenAI, Anthropic, or Google Gemini for higher-quality transcription, suggestions, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Faster Processing",
                    description: "Cloud providers can be faster than on-device models"
                )
                FeatureRow(
                    icon: "sparkles",
                    title: "More Capable Models",
                    description: "Access GPT-4o, Claude, Gemini, and more"
                )
                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "Your API Keys",
                    description: "Keys are stored securely in macOS Keychain"
                )
            }
            .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)

                Text("You can configure cloud providers anytime in Settings > AI Providers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .frame(maxWidth: 400)

            Spacer()
        }
    }
}

struct DoneStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("You're ready to start using Gophy")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Start Using Gophy") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 24)

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
