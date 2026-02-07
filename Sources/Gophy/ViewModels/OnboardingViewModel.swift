import Foundation
import Observation
import AVFoundation
import AppKit
import EventKit

@MainActor
@Observable
final class OnboardingViewModel {
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case language = 2
        case calendar = 3
        case modelSetup = 4
        case done = 5
    }

    enum ProviderChoice {
        case local
        case cloud
    }

    var currentStep: OnboardingStep = .welcome
    var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    var isCheckingPermissions: Bool = false
    var languagePreference: AppLanguage = .auto
    var calendarConnected: Bool = false
    var isConnectingCalendar: Bool = false
    var calendarSkipped: Bool = false
    var eventKitGranted: Bool = false

    // Per-capability provider choices
    var sttChoice: ProviderChoice = .local
    var textGenChoice: ProviderChoice = .local
    var visionChoice: ProviderChoice = .local
    var embeddingChoice: ProviderChoice = .local

    private let modelManagerViewModel: ModelManagerViewModel

    init(modelManagerViewModel: ModelManagerViewModel) {
        self.modelManagerViewModel = modelManagerViewModel
        checkPermissions()
        checkEventKitStatus()
    }

    var hasDownloadedModels: Bool {
        modelManagerViewModel.hasDownloadedModels
    }

    var totalModelDiskUsage: Double {
        modelManagerViewModel.totalDiskUsageGB
    }

    var models: [ModelDefinition] {
        modelManagerViewModel.models
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        modelManagerViewModel.isDownloaded(model)
    }

    func isDownloading(_ model: ModelDefinition) -> Bool {
        modelManagerViewModel.isDownloading(model)
    }

    func downloadProgress(for model: ModelDefinition) -> DownloadProgress? {
        modelManagerViewModel.downloadProgress[model.id]
    }

    func downloadModel(_ model: ModelDefinition) {
        modelManagerViewModel.downloadModel(model)
    }

    func cancelDownload(_ model: ModelDefinition) {
        modelManagerViewModel.cancelDownload(model)
    }

    func checkPermissions() {
        isCheckingPermissions = true
        microphonePermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isCheckingPermissions = false
    }

    func requestMicrophonePermission() async {
        isCheckingPermissions = true
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphonePermissionStatus = granted ? .authorized : .denied
        isCheckingPermissions = false
    }

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func nextStep() {
        if currentStep.rawValue < OnboardingStep.allCases.count - 1 {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .welcome
        }
    }

    func previousStep() {
        if currentStep.rawValue > 0 {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
        }
    }

    func updateLanguagePreference(_ language: AppLanguage) {
        languagePreference = language
        UserDefaults.standard.set(language.rawValue, forKey: "languagePreference")
    }

    func canProceed(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome:
            return true
        case .permissions:
            return microphonePermissionStatus == .authorized
        case .language:
            return true
        case .calendar:
            return true
        case .modelSetup:
            // Require at least STT to be configured (either local model downloaded OR cloud selected)
            if sttChoice == .local {
                // Check if at least one STT model is downloaded
                let sttModels = models.filter { $0.type == .stt }
                return sttModels.contains { isDownloaded($0) }
            } else {
                // Cloud chosen, can proceed (will configure in settings)
                return true
            }
        case .done:
            return true
        }
    }

    func completeOnboarding() {
        // Persist provider choices to UserDefaults (matching ProviderRegistry keys)
        let defaults = UserDefaults.standard

        if sttChoice == .cloud {
            defaults.set("cloud", forKey: "selectedSTTProvider")
        } else {
            defaults.set("local", forKey: "selectedSTTProvider")
        }

        if textGenChoice == .cloud {
            defaults.set("cloud", forKey: "selectedTextGenProvider")
        } else {
            defaults.set("local", forKey: "selectedTextGenProvider")
        }

        if visionChoice == .cloud {
            defaults.set("cloud", forKey: "selectedVisionProvider")
        } else {
            defaults.set("local", forKey: "selectedVisionProvider")
        }

        if embeddingChoice == .cloud {
            defaults.set("cloud", forKey: "selectedEmbeddingProvider")
        } else {
            defaults.set("local", forKey: "selectedEmbeddingProvider")
        }

        defaults.set(true, forKey: "hasCompletedOnboarding")
    }

    static func hasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    private func checkEventKitStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        eventKitGranted = (status == .authorized || status == .fullAccess)
    }

    func requestEventKitAccess() async {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            eventKitGranted = granted
        } catch {
            eventKitGranted = false
        }
    }

    func skipCalendarSetup() {
        calendarSkipped = true
    }
}
