import Foundation

@MainActor
@Observable
public final class DocumentDetailViewModel {
    public var chunks: [DocumentChunkRecord] = []
    public var errorMessage: String?

    private let documentRepository: DocumentRepository

    public init(documentRepository: DocumentRepository) {
        self.documentRepository = documentRepository
    }

    public func loadChunks(documentId: String) async {
        do {
            chunks = try await documentRepository.getChunks(documentId: documentId)
        } catch {
            errorMessage = "Failed to load chunks: \(error.localizedDescription)"
        }
    }

    public func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
