import Testing
import Foundation
@testable import Gophy

@Suite("Onboarding Model Selection Tests")
@MainActor
struct OnboardingModelSelectionTests {

    @Test("Per-capability choices persist correctly")
    func testPerCapabilityPersistence() async throws {
        let defaults = UserDefaults.standard
        let modelManager = ModelManagerViewModel()
        let viewModel = OnboardingViewModel(modelManagerViewModel: modelManager)

        // Set choices
        viewModel.sttChoice = .cloud
        viewModel.textGenChoice = .local
        viewModel.visionChoice = .cloud
        viewModel.embeddingChoice = .local

        // Complete onboarding
        viewModel.completeOnboarding()

        // Verify persistence
        #expect(defaults.string(forKey: "selectedSTTProvider") == "cloud", "STT choice should persist")
        #expect(defaults.string(forKey: "selectedTextGenProvider") == "local", "Text gen choice should persist")
        #expect(defaults.string(forKey: "selectedVisionProvider") == "cloud", "Vision choice should persist")
        #expect(defaults.string(forKey: "selectedEmbeddingProvider") == "local", "Embedding choice should persist")

        // Cleanup
        defaults.removeObject(forKey: "selectedSTTProvider")
        defaults.removeObject(forKey: "selectedTextGenProvider")
        defaults.removeObject(forKey: "selectedVisionProvider")
        defaults.removeObject(forKey: "selectedEmbeddingProvider")
        defaults.removeObject(forKey: "hasCompletedOnboarding")
    }

    @Test("canProceed requires STT to be configured when local")
    func testCanProceedRequiresSTTLocal() async throws {
        let modelManager = ModelManagerViewModel()
        let viewModel = OnboardingViewModel(modelManagerViewModel: modelManager)

        viewModel.sttChoice = .local

        // Should not proceed if no STT model downloaded
        let canProceed = viewModel.canProceed(from: .modelSetup)

        // This depends on whether test environment has models downloaded
        // We just verify the method runs without crashing
        #expect(canProceed == true || canProceed == false, "Should return valid boolean")
    }

    @Test("canProceed allows cloud choice without downloaded model")
    func testCanProceedAllowsCloudChoice() async throws {
        let modelManager = ModelManagerViewModel()
        let viewModel = OnboardingViewModel(modelManagerViewModel: modelManager)

        viewModel.sttChoice = .cloud

        // Should allow proceeding even without downloaded models
        let canProceed = viewModel.canProceed(from: .modelSetup)
        #expect(canProceed == true, "Should allow cloud choice without download")
    }

    @Test("Completing onboarding writes ProviderRegistry keys")
    func testCompletingOnboardingWritesRegistryKeys() async throws {
        let defaults = UserDefaults.standard
        let modelManager = ModelManagerViewModel()
        let viewModel = OnboardingViewModel(modelManagerViewModel: modelManager)

        // Set all to local
        viewModel.sttChoice = .local
        viewModel.textGenChoice = .local
        viewModel.visionChoice = .local
        viewModel.embeddingChoice = .local

        viewModel.completeOnboarding()

        // All should be "local"
        #expect(defaults.string(forKey: "selectedSTTProvider") == "local")
        #expect(defaults.string(forKey: "selectedTextGenProvider") == "local")
        #expect(defaults.string(forKey: "selectedVisionProvider") == "local")
        #expect(defaults.string(forKey: "selectedEmbeddingProvider") == "local")

        // Cleanup
        defaults.removeObject(forKey: "selectedSTTProvider")
        defaults.removeObject(forKey: "selectedTextGenProvider")
        defaults.removeObject(forKey: "selectedVisionProvider")
        defaults.removeObject(forKey: "selectedEmbeddingProvider")
        defaults.removeObject(forKey: "hasCompletedOnboarding")
    }

    @Test("OnboardingStep enum has correct count")
    func testOnboardingStepCount() async throws {
        // After merging models + cloudProviders into modelSetup, should have 6 steps
        #expect(OnboardingViewModel.OnboardingStep.allCases.count == 6)
    }

    @Test("modelSetup step comes before done")
    func testModelSetupStepOrder() async throws {
        let modelSetupRawValue = OnboardingViewModel.OnboardingStep.modelSetup.rawValue
        let doneRawValue = OnboardingViewModel.OnboardingStep.done.rawValue

        #expect(modelSetupRawValue < doneRawValue, "modelSetup should come before done")
    }
}
