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
        case models = 4
        case cloudProviders = 5
        case done = 6
    }

    var currentStep: OnboardingStep = .welcome
    var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    var isCheckingPermissions: Bool = false
    var languagePreference: AppLanguage = .auto
    var calendarConnected: Bool = false
    var isConnectingCalendar: Bool = false
    var calendarSkipped: Bool = false
    var eventKitGranted: Bool = false

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
        case .models:
            return hasDownloadedModels
        case .cloudProviders:
            return true
        case .done:
            return true
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
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
