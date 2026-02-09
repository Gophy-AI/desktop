import Foundation
import Observation
import AppKit
import EventKit

/// Display-only info about a voice pattern for the settings UI.
public struct VoicePatternInfo: Sendable {
    public let toolName: String
    public let description: String
}

/// Display-only info about a keyboard shortcut for the settings UI.
public struct ShortcutInfo: Sendable {
    public let toolName: String
    public let description: String
}

@MainActor
@Observable
public final class SettingsViewModel {
    private let audioDeviceManager: AudioDeviceManager
    private let storageManager: StorageManager
    private let registry: ModelRegistryProtocol
    private let keychainService: any KeychainServiceProtocol
    private var authService: GoogleAuthService?
    private var calendarSyncService: (any CalendarSyncServiceProtocol)?
    private var eventKitService: (any EventKitServiceProtocol)?
    private var providerRegistry: ProviderRegistry?

    var availableInputDevices: [AudioDevice] = []
    var selectedDevice: AudioDevice?
    var systemAudioEnabled: Bool = false
    var vadSensitivity: Double = 0.5
    var autoSuggestInterval: Double = 30.0

    var inferenceMaxTokens: Double = 2048
    var inferenceTemperature: Double = 0.7
    var thinkingEnabled: Bool = true
    var ocrMaxTokens: Double = 4096

    var databaseLocation: String
    var totalStorageGB: Double = 0.0
    var totalModelStorageGB: Double = 0.0

    var languagePreference: AppLanguage = .auto

    var selectedTextGenModelId: String = "qwen2.5-7b-instruct-4bit"
    var selectedSTTModelId: String = "whisperkit-large-v3-turbo"
    var selectedOCRModelId: String = "qwen2.5-vl-7b-instruct-4bit"
    var selectedEmbeddingModelId: String = "multilingual-e5-small"

    var showClearDataConfirmation: Bool = false
    var errorMessage: String?

    // Automation settings
    var automationsEnabled: Bool = true
    var voiceCommandsEnabled: Bool = true
    var keyboardShortcutsEnabled: Bool = true
    var alwaysAllowedTools: Set<String> = []

    var voicePatterns: [VoicePatternInfo] {
        VoicePattern.defaults.map {
            VoicePatternInfo(toolName: $0.toolName, description: $0.description)
        }
    }

    var keyboardShortcuts: [ShortcutInfo] {
        AutomationShortcut.defaults.map {
            ShortcutInfo(toolName: $0.toolName, description: $0.description)
        }
    }

    var confirmableTools: [String] {
        ["remember", "generate_summary"]
    }

    // Provider settings
    var configuredProviderIds: Set<String> = []
    var providerErrorMessage: String?

    // Calendar settings
    var isGoogleSignedIn: Bool = false
    var googleUserEmail: String?
    var isSigningIn: Bool = false
    var calendarErrorMessage: String?
    var calendarAutoStartEnabled: Bool = true
    var calendarAutoStartOnlyVideo: Bool = true
    var calendarAutoStartLeadTime: Double = 60.0
    var calendarSyncInterval: Double = 300.0
    var calendarWritebackEnabled: Bool = false
    var lastCalendarSyncTime: Date?
    var isSyncingCalendar: Bool = false
    var eventKitAccessGranted: Bool = false

    private var deviceListenerTask: Task<Void, Never>?

    init(
        audioDeviceManager: AudioDeviceManager,
        storageManager: StorageManager,
        registry: ModelRegistryProtocol,
        keychainService: any KeychainServiceProtocol = KeychainService(),
        authService: GoogleAuthService? = nil,
        calendarSyncService: (any CalendarSyncServiceProtocol)? = nil,
        eventKitService: (any EventKitServiceProtocol)? = nil
    ) {
        self.audioDeviceManager = audioDeviceManager
        self.storageManager = storageManager
        self.registry = registry
        self.keychainService = keychainService
        self.authService = authService
        self.calendarSyncService = calendarSyncService
        self.eventKitService = eventKitService
        self.databaseLocation = storageManager.databaseDirectory.path

        loadSettings()
        startDeviceListener()
        calculateStorage()
        loadCalendarSettings()
        loadAutomationSettings()
        refreshConfiguredProviders()
    }


    private func loadSettings() {
        let defaults = UserDefaults.standard

        if let savedDeviceUID = defaults.string(forKey: "selectedAudioDeviceUID") {
            do {
                let devices = try audioDeviceManager.listInputDevices()
                selectedDevice = devices.first { $0.uid == savedDeviceUID }
            } catch {
                print("Error loading audio devices: \(error)")
            }
        }

        systemAudioEnabled = defaults.bool(forKey: "systemAudioEnabled")
        vadSensitivity = defaults.double(forKey: "vadSensitivity")
        if vadSensitivity == 0 {
            vadSensitivity = 0.5
        }

        autoSuggestInterval = defaults.double(forKey: "autoSuggestInterval")
        if autoSuggestInterval == 0 {
            autoSuggestInterval = 30.0
        }

        if let savedLanguage = defaults.string(forKey: "languagePreference"),
           let language = AppLanguage(rawValue: savedLanguage) {
            languagePreference = language
        }

        if let savedTextGenModel = defaults.string(forKey: "selectedTextGenModelId") {
            selectedTextGenModelId = savedTextGenModel
        }

        if let savedSTTModel = defaults.string(forKey: "selectedSTTModelId") {
            selectedSTTModelId = savedSTTModel
        }

        if let savedOCRModel = defaults.string(forKey: "selectedOCRModelId") {
            selectedOCRModelId = savedOCRModel
        }

        if let savedEmbeddingModel = defaults.string(forKey: "selectedEmbeddingModelId") {
            selectedEmbeddingModelId = savedEmbeddingModel
        }

        let maxTokensValue = defaults.integer(forKey: "inference.maxTokens")
        if maxTokensValue > 0 {
            inferenceMaxTokens = Double(maxTokensValue)
        }

        let tempValue = defaults.double(forKey: "inference.temperature")
        if tempValue > 0 {
            inferenceTemperature = tempValue
        }

        let thinkingKey = "inference.thinkingEnabled"
        if defaults.object(forKey: thinkingKey) != nil {
            thinkingEnabled = defaults.bool(forKey: thinkingKey)
        } else {
            thinkingEnabled = true
        }

        let ocrMaxTokensValue = defaults.integer(forKey: "inference.ocrMaxTokens")
        if ocrMaxTokensValue > 0 {
            ocrMaxTokens = Double(ocrMaxTokensValue)
        }
    }

    private func startDeviceListener() {
        deviceListenerTask = Task {
            for await devices in audioDeviceManager.deviceChangeStream {
                self.availableInputDevices = devices

                if selectedDevice == nil && !devices.isEmpty {
                    selectedDevice = devices.first
                }
            }
        }

        do {
            availableInputDevices = try audioDeviceManager.listInputDevices()
            if selectedDevice == nil && !availableInputDevices.isEmpty {
                selectedDevice = availableInputDevices.first
            }
        } catch {
            print("Error listing initial devices: \(error)")
        }
    }

    func selectInputDevice(_ device: AudioDevice) {
        selectedDevice = device
        audioDeviceManager.selectDevice(device)

        let defaults = UserDefaults.standard
        defaults.set(device.uid, forKey: "selectedAudioDeviceUID")
    }

    func toggleSystemAudio() {
        systemAudioEnabled.toggle()
        let defaults = UserDefaults.standard
        defaults.set(systemAudioEnabled, forKey: "systemAudioEnabled")
    }

    func updateVADSensitivity(_ value: Double) {
        vadSensitivity = value
        let defaults = UserDefaults.standard
        defaults.set(vadSensitivity, forKey: "vadSensitivity")
    }

    func updateAutoSuggestInterval(_ value: Double) {
        autoSuggestInterval = value
        let defaults = UserDefaults.standard
        defaults.set(autoSuggestInterval, forKey: "autoSuggestInterval")
    }

    func updateLanguagePreference(_ language: AppLanguage) {
        languagePreference = language
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: "languagePreference")
    }

    func updateSelectedTextGenModel(_ modelId: String) {
        selectedTextGenModelId = modelId
        let defaults = UserDefaults.standard
        defaults.set(modelId, forKey: "selectedTextGenModelId")
    }

    func updateSelectedSTTModel(_ modelId: String) {
        selectedSTTModelId = modelId
        let defaults = UserDefaults.standard
        defaults.set(modelId, forKey: "selectedSTTModelId")
    }

    func updateSelectedOCRModel(_ modelId: String) {
        selectedOCRModelId = modelId
        let defaults = UserDefaults.standard
        defaults.set(modelId, forKey: "selectedOCRModelId")
    }

    func updateSelectedEmbeddingModel(_ modelId: String) {
        selectedEmbeddingModelId = modelId
        let defaults = UserDefaults.standard
        defaults.set(modelId, forKey: "selectedEmbeddingModelId")
    }

    func updateInferenceMaxTokens(_ value: Double) {
        inferenceMaxTokens = value
        UserDefaults.standard.set(Int(value), forKey: "inference.maxTokens")
    }

    func updateInferenceTemperature(_ value: Double) {
        inferenceTemperature = value
        UserDefaults.standard.set(value, forKey: "inference.temperature")
    }

    func updateThinkingEnabled(_ enabled: Bool) {
        thinkingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "inference.thinkingEnabled")
    }

    func updateOCRMaxTokens(_ value: Double) {
        ocrMaxTokens = value
        UserDefaults.standard.set(Int(value), forKey: "inference.ocrMaxTokens")
    }

    var availableTextGenModels: [ModelDefinition] {
        registry.availableModels().filter { $0.type == .textGen }
    }

    var availableSTTModels: [ModelDefinition] {
        registry.availableModels().filter { $0.type == .stt }
    }

    var availableOCRModels: [ModelDefinition] {
        registry.availableModels().filter { $0.type == .ocr }
    }

    var availableEmbeddingModels: [ModelDefinition] {
        registry.availableModels().filter { $0.type == .embedding }
    }

    func openDatabaseInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageManager.databaseDirectory.path)
    }

    func calculateStorage() {
        let fileManager = FileManager.default

        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(
            at: storageManager.databaseDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        totalStorageGB = Double(totalSize) / 1_000_000_000

        var modelSize: Int64 = 0

        // Check primary models directory
        modelSize += calculateDirectorySize(at: storageManager.modelsDirectory)

        // Also check alternative models directory (sandbox/non-sandbox counterpart)
        if let altDir = storageManager.alternativeModelsDirectory {
            modelSize += calculateDirectorySize(at: altDir)
        }

        totalModelStorageGB = Double(modelSize) / 1_000_000_000
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0

        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }

    func confirmClearData() {
        showClearDataConfirmation = true
    }

    func clearAllData() async {
        do {
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: storageManager.databaseDirectory.path) {
                try fileManager.removeItem(at: storageManager.databaseDirectory)
            }

            try fileManager.createDirectory(
                at: storageManager.databaseDirectory,
                withIntermediateDirectories: true
            )

            calculateStorage()
            errorMessage = nil
            showClearDataConfirmation = false
        } catch {
            errorMessage = "Failed to clear data: \(error.localizedDescription)"
            showClearDataConfirmation = false
        }
    }

    // MARK: - Calendar Settings

    private func loadCalendarSettings() {
        let defaults = UserDefaults.standard

        let autoStartKey = "calendarAutoStartEnabled"
        if defaults.object(forKey: autoStartKey) != nil {
            calendarAutoStartEnabled = defaults.bool(forKey: autoStartKey)
        }

        let onlyVideoKey = "calendarAutoStartOnlyVideo"
        if defaults.object(forKey: onlyVideoKey) != nil {
            calendarAutoStartOnlyVideo = defaults.bool(forKey: onlyVideoKey)
        }

        let leadTimeValue = defaults.double(forKey: "calendarAutoStartLeadTime")
        if leadTimeValue > 0 {
            calendarAutoStartLeadTime = leadTimeValue
        }

        let syncIntervalValue = defaults.double(forKey: "calendarSyncInterval")
        if syncIntervalValue > 0 {
            calendarSyncInterval = syncIntervalValue
        }

        calendarWritebackEnabled = defaults.bool(forKey: "calendarWritebackEnabled")

        if let lastSyncTimestamp = defaults.object(forKey: "calendarLastSyncTime") as? Date {
            lastCalendarSyncTime = lastSyncTimestamp
        }

        let ekStatus = EKEventStore.authorizationStatus(for: .event)
        eventKitAccessGranted = (ekStatus == .authorized || ekStatus == .fullAccess)

        ensureCalendarServices()

        if eventKitService == nil {
            eventKitService = EventKitService()
        }

        Task {
            await refreshGoogleAuthStatus()
        }
    }

    private func ensureCalendarServices() {
        if authService == nil {
            let config = GoogleCalendarConfig()
            guard config.isConfigured else { return }
            let newAuthService = GoogleAuthService(config: config)
            authService = newAuthService

            if calendarSyncService == nil {
                let ekService = eventKitService ?? EventKitService()
                eventKitService = ekService
                let apiClient = GoogleCalendarAPIClient(authService: newAuthService)
                calendarSyncService = CalendarSyncService(
                    apiClient: apiClient,
                    eventKitService: ekService
                )
            }
        }
    }

    private func refreshGoogleAuthStatus() async {
        ensureCalendarServices()
        guard let authService = authService else { return }
        isGoogleSignedIn = await authService.isSignedIn
        googleUserEmail = await authService.userEmail
    }

    func signInGoogle() async {
        ensureCalendarServices()
        guard let authService = authService else {
            calendarErrorMessage = "Calendar service not initialized"
            return
        }

        isSigningIn = true
        calendarErrorMessage = nil

        do {
            try await authService.signIn(presentingWindow: nil)
            isGoogleSignedIn = await authService.isSignedIn
            googleUserEmail = await authService.userEmail
        } catch {
            calendarErrorMessage = error.localizedDescription
        }

        isSigningIn = false
    }

    func signOutGoogle() {
        ensureCalendarServices()
        guard let authService = authService else { return }

        Task {
            do {
                try await authService.signOut()
                isGoogleSignedIn = false
                googleUserEmail = nil
                calendarErrorMessage = nil
            } catch {
                calendarErrorMessage = "Failed to sign out: \(error.localizedDescription)"
            }
        }
    }

    func updateCalendarAutoStart(_ enabled: Bool) {
        calendarAutoStartEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "calendarAutoStartEnabled")
    }

    func updateCalendarAutoStartOnlyVideo(_ onlyVideo: Bool) {
        calendarAutoStartOnlyVideo = onlyVideo
        UserDefaults.standard.set(onlyVideo, forKey: "calendarAutoStartOnlyVideo")
    }

    func updateCalendarAutoStartLeadTime(_ seconds: Double) {
        calendarAutoStartLeadTime = seconds
        UserDefaults.standard.set(seconds, forKey: "calendarAutoStartLeadTime")
    }

    func updateCalendarSyncInterval(_ seconds: Double) {
        calendarSyncInterval = seconds
        UserDefaults.standard.set(seconds, forKey: "calendarSyncInterval")
    }

    func updateCalendarWriteback(_ enabled: Bool) {
        calendarWritebackEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "calendarWritebackEnabled")
    }

    func syncCalendarNow() async {
        ensureCalendarServices()
        guard let syncService = calendarSyncService else { return }

        isSyncingCalendar = true
        calendarErrorMessage = nil
        do {
            let events = try await syncService.syncNow()
            lastCalendarSyncTime = Date()
            UserDefaults.standard.set(lastCalendarSyncTime, forKey: "calendarLastSyncTime")
            calendarErrorMessage = "Synced \(events.count) event(s)"
        } catch {
            calendarErrorMessage = "Sync failed: \(error.localizedDescription)"
        }
        isSyncingCalendar = false
    }

    func requestEventKitAccess() async {
        guard let eventKitService = eventKitService else {
            let service = EventKitService()
            do {
                let granted = try await service.requestAccess()
                eventKitAccessGranted = granted
            } catch {
                calendarErrorMessage = error.localizedDescription
            }
            return
        }

        do {
            let granted = try await eventKitService.requestAccess()
            eventKitAccessGranted = granted
        } catch {
            calendarErrorMessage = error.localizedDescription
        }
    }

    func setCalendarServices(
        authService: GoogleAuthService,
        calendarSyncService: any CalendarSyncServiceProtocol,
        eventKitService: any EventKitServiceProtocol
    ) {
        self.authService = authService
        self.calendarSyncService = calendarSyncService
        self.eventKitService = eventKitService
        loadCalendarSettings()
    }

    // MARK: - Automation Settings

    private func loadAutomationSettings() {
        let defaults = UserDefaults.standard

        let enabledKey = "automations.enabled"
        if defaults.object(forKey: enabledKey) != nil {
            automationsEnabled = defaults.bool(forKey: enabledKey)
        }

        let voiceKey = "automations.voiceCommands.enabled"
        if defaults.object(forKey: voiceKey) != nil {
            voiceCommandsEnabled = defaults.bool(forKey: voiceKey)
        }

        let keyboardKey = "automations.shortcuts.enabled"
        if defaults.object(forKey: keyboardKey) != nil {
            keyboardShortcutsEnabled = defaults.bool(forKey: keyboardKey)
        }

        if let saved = defaults.stringArray(forKey: "automations.alwaysAllowedTools") {
            alwaysAllowedTools = Set(saved)
        }
    }

    func updateAutomationsEnabled(_ enabled: Bool) {
        automationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "automations.enabled")
    }

    func updateVoiceCommandsEnabled(_ enabled: Bool) {
        voiceCommandsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "automations.voiceCommands.enabled")
    }

    func updateKeyboardShortcutsEnabled(_ enabled: Bool) {
        keyboardShortcutsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "automations.shortcuts.enabled")
    }

    func resetAlwaysAllowed() {
        alwaysAllowedTools.removeAll()
        UserDefaults.standard.removeObject(forKey: "automations.alwaysAllowedTools")
    }

    // MARK: - Provider Management

    func setProviderRegistry(_ registry: ProviderRegistry) {
        self.providerRegistry = registry
        refreshConfiguredProviders()
    }

    private func refreshConfiguredProviders() {
        if let registry = providerRegistry {
            configuredProviderIds = Set(registry.configuredProviders())
        } else {
            configuredProviderIds = Set((try? keychainService.listProviderIds()) ?? [])
        }
    }

    func isProviderConfigured(_ providerId: String) -> Bool {
        configuredProviderIds.contains(providerId)
    }

    func configuredProviderConfigs(for capability: ProviderCapability) -> [ProviderConfiguration] {
        ProviderCatalog.all.filter { config in
            configuredProviderIds.contains(config.id) && config.supportedCapabilities.contains(capability)
        }
    }

    private func defaultsKeys(for capability: ProviderCapability) -> (providerKey: String, modelKey: String) {
        switch capability {
        case .textGeneration:
            return ("selectedTextGenProvider", "selectedTextGenModel")
        case .embedding:
            return ("selectedEmbeddingProvider", "selectedEmbeddingModel")
        case .speechToText:
            return ("selectedSTTProvider", "selectedSTTModel")
        case .vision:
            return ("selectedVisionProvider", "selectedVisionModel")
        case .textToSpeech:
            return ("selectedTTSProvider", "selectedTTSModel")
        }
    }

    func selectedProviderIdFor(_ capability: ProviderCapability) -> String {
        if let registry = providerRegistry {
            return registry.selectedProviderId(for: capability)
        }
        let (providerKey, _) = defaultsKeys(for: capability)
        return UserDefaults.standard.string(forKey: providerKey) ?? "local"
    }

    func selectedModelIdFor(_ capability: ProviderCapability) -> String {
        if let registry = providerRegistry {
            return registry.selectedModelId(for: capability)
        }
        let (_, modelKey) = defaultsKeys(for: capability)
        return UserDefaults.standard.string(forKey: modelKey) ?? ""
    }

    func availableCloudModels(for capability: ProviderCapability, providerId: String) -> [CloudModelDefinition] {
        guard providerId != "local",
              let config = ProviderCatalog.provider(id: providerId) else {
            return []
        }
        return config.availableModels.filter { $0.capability == capability }
    }

    func selectCloudProvider(for capability: ProviderCapability, providerId: String, modelId: String) {
        if let registry = providerRegistry {
            registry.selectProvider(for: capability, providerId: providerId, modelId: modelId)
        } else {
            let (providerKey, modelKey) = defaultsKeys(for: capability)
            UserDefaults.standard.set(providerId, forKey: providerKey)
            UserDefaults.standard.set(modelId, forKey: modelKey)
        }
    }

    func saveProviderAPIKey(providerId: String, apiKey: String) {
        do {
            if let registry = providerRegistry {
                try registry.configureProvider(id: providerId, apiKey: apiKey)
            } else {
                try keychainService.save(apiKey: apiKey, for: providerId)
            }
            refreshConfiguredProviders()
            providerErrorMessage = nil
        } catch {
            providerErrorMessage = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    func removeProviderAPIKey(providerId: String) {
        do {
            if let registry = providerRegistry {
                try registry.removeProvider(id: providerId)
            } else {
                try keychainService.delete(for: providerId)
            }
            refreshConfiguredProviders()
            providerErrorMessage = nil
        } catch {
            providerErrorMessage = "Failed to remove API key: \(error.localizedDescription)"
        }
    }

    func testProviderConnection(providerId: String) async -> TestConnectionResult {
        let status: ProviderHealthStatus

        if let registry = providerRegistry {
            status = await registry.checkHealth(providerId: providerId)
        } else {
            status = await checkHealthDirectly(providerId: providerId)
        }

        switch status {
        case .healthy:
            return TestConnectionResult(isHealthy: true, message: "Connection successful")
        case .degraded(let msg):
            return TestConnectionResult(isHealthy: false, message: "Degraded: \(msg)")
        case .unavailable(let msg):
            return TestConnectionResult(isHealthy: false, message: msg)
        }
    }

    private func checkHealthDirectly(providerId: String) async -> ProviderHealthStatus {
        guard providerId != "local" else {
            return .healthy
        }

        let apiKey: String
        do {
            guard let retrieved = try keychainService.retrieve(for: providerId), !retrieved.isEmpty else {
                return .unavailable("No API key configured")
            }
            apiKey = retrieved
        } catch {
            return .unavailable("Failed to retrieve API key")
        }

        if providerId == "anthropic" {
            let provider = AnthropicProvider(apiKey: apiKey)
            return await provider.healthCheck()
        }

        guard let config = ProviderCatalog.provider(id: providerId) else {
            return .unavailable("Unknown provider: \(providerId)")
        }

        let firstTextModel = config.availableModels.first { $0.capability == .textGeneration }?.id
        let firstEmbModel = config.availableModels.first { $0.capability == .embedding }?.id

        let provider = OpenAICompatibleProvider(
            providerId: config.id,
            baseURL: config.baseURL,
            apiKey: apiKey,
            textGenModel: firstTextModel,
            embeddingModel: firstEmbModel
        )
        return await provider.healthCheck()
    }

    func isCloudProvider(for capability: ProviderCapability) -> Bool {
        return selectedProviderIdFor(capability) != "local"
    }
}
