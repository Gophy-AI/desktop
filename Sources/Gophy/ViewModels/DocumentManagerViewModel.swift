import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
public final class DocumentManagerViewModel {
    public var documents: [DocumentRecord] = []
    public var isProcessing: Bool = false
    public var errorMessage: String?
    public var selectedDocument: DocumentRecord?

    private let documentRepository: DocumentRepository
    private let documentProcessor: DocumentProcessor

    public init(documentRepository: DocumentRepository, documentProcessor: DocumentProcessor) {
        self.documentRepository = documentRepository
        self.documentProcessor = documentProcessor
    }

    public func loadDocuments() async {
        do {
            documents = try await documentRepository.listAll()
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
        }
    }

    public func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .plainText]

        panel.begin { response in
            if response == .OK {
                Task { @MainActor in
                    for url in panel.urls {
                        await self.processDocument(url: url)
                    }
                }
            }
        }
    }

    public func processDocument(url: URL) async {
        isProcessing = true
        errorMessage = nil

        do {
            _ = try await documentProcessor.process(fileURL: url)
            await loadDocuments()
        } catch {
            errorMessage = "Failed to process document: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    public func deleteDocument(_ document: DocumentRecord) async {
        do {
            try await documentRepository.delete(id: document.id)
            await loadDocuments()
        } catch {
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
        }
    }

    public func typeIcon(for type: String) -> String {
        switch type.lowercased() {
        case "pdf":
            return "doc.fill"
        case "png", "jpg", "jpeg":
            return "photo"
        case "txt", "md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    public func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
