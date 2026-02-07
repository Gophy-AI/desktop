import Testing
import Foundation
@testable import Gophy

@Suite("SettingsViewModel Model Selection Tests")
@MainActor
struct SettingsViewModelModelSelectionTests {

    @Test("Updating text gen model persists to UserDefaults")
    func testUpdateTextGenModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-textgen-model"
        viewModel.updateSelectedTextGenModel(testModelId)

        let saved = defaults.string(forKey: "selectedTextGenModelId")
        #expect(saved == testModelId, "Text gen model should be persisted")
        #expect(viewModel.selectedTextGenModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedTextGenModelId")
    }

    @Test("Updating STT model persists to UserDefaults")
    func testUpdateSTTModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-stt-model"
        viewModel.updateSelectedSTTModel(testModelId)

        let saved = defaults.string(forKey: "selectedSTTModelId")
        #expect(saved == testModelId, "STT model should be persisted")
        #expect(viewModel.selectedSTTModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedSTTModelId")
    }

    @Test("Updating OCR model persists to UserDefaults")
    func testUpdateOCRModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-ocr-model"
        viewModel.updateSelectedOCRModel(testModelId)

        let saved = defaults.string(forKey: "selectedOCRModelId")
        #expect(saved == testModelId, "OCR model should be persisted")
        #expect(viewModel.selectedOCRModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedOCRModelId")
    }

    @Test("Updating embedding model persists to UserDefaults")
    func testUpdateEmbeddingModel() async throws {
        let defaults = UserDefaults.standard
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let testModelId = "test-embedding-model"
        viewModel.updateSelectedEmbeddingModel(testModelId)

        let saved = defaults.string(forKey: "selectedEmbeddingModelId")
        #expect(saved == testModelId, "Embedding model should be persisted")
        #expect(viewModel.selectedEmbeddingModelId == testModelId, "ViewModel should update")

        // Cleanup
        defaults.removeObject(forKey: "selectedEmbeddingModelId")
    }

    @Test("availableSTTModels returns only STT models")
    func testAvailableSTTModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let sttModels = viewModel.availableSTTModels
        #expect(!sttModels.isEmpty, "Should have STT models")

        for model in sttModels {
            #expect(model.type == .stt, "All models should be STT type")
        }
    }

    @Test("availableTextGenModels returns only textGen models")
    func testAvailableTextGenModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let textGenModels = viewModel.availableTextGenModels
        #expect(!textGenModels.isEmpty, "Should have text gen models")

        for model in textGenModels {
            #expect(model.type == .textGen, "All models should be textGen type")
        }
    }

    @Test("availableOCRModels returns only OCR models")
    func testAvailableOCRModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let ocrModels = viewModel.availableOCRModels
        #expect(!ocrModels.isEmpty, "Should have OCR models")

        for model in ocrModels {
            #expect(model.type == .ocr, "All models should be OCR type")
        }
    }

    @Test("availableEmbeddingModels returns only embedding models")
    func testAvailableEmbeddingModels() async throws {
        let audioManager = AudioDeviceManager()
        let storageManager = StorageManager.shared
        let registry = DynamicModelRegistry()

        let viewModel = SettingsViewModel(
            audioDeviceManager: audioManager,
            storageManager: storageManager,
            registry: registry
        )

        let embeddingModels = viewModel.availableEmbeddingModels
        #expect(!embeddingModels.isEmpty, "Should have embedding models")

        for model in embeddingModels {
            #expect(model.type == .embedding, "All models should be embedding type")
        }
    }
}
