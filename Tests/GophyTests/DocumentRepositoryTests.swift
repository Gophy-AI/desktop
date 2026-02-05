import XCTest
import Foundation
import GRDB
@testable import Gophy

final class DocumentRepositoryTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!
    var repository: DocumentRepository!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyDocumentRepoTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        repository = DocumentRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testCreateDocumentAndAddChunks() async throws {
        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "pending",
            pageCount: 5,
            createdAt: Date()
        )

        try await repository.create(document)

        let chunk1 = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "First chunk of content",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        let chunk2 = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Second chunk of content",
            chunkIndex: 1,
            pageNumber: 1,
            createdAt: Date()
        )

        let chunk3 = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Third chunk on page 2",
            chunkIndex: 2,
            pageNumber: 2,
            createdAt: Date()
        )

        try await repository.addChunk(chunk1)
        try await repository.addChunk(chunk2)
        try await repository.addChunk(chunk3)

        let chunks = try await repository.getChunks(documentId: documentId)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].chunkIndex, 0, "Chunks should be ordered by chunkIndex")
        XCTAssertEqual(chunks[1].chunkIndex, 1)
        XCTAssertEqual(chunks[2].chunkIndex, 2)
    }

    func testDeleteCascadesToChunks() async throws {
        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 1,
            createdAt: Date()
        )

        try await repository.create(document)

        let chunk = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Test chunk",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        try await repository.addChunk(chunk)

        let chunksBeforeDelete = try await repository.getChunks(documentId: documentId)
        XCTAssertEqual(chunksBeforeDelete.count, 1)

        try await repository.delete(id: documentId)

        let documentAfterDelete = try await repository.get(id: documentId)
        XCTAssertNil(documentAfterDelete)

        let chunksAfterDelete = try await repository.getChunks(documentId: documentId)
        XCTAssertEqual(chunksAfterDelete.count, 0, "Chunks should be deleted with document")
    }

    func testStatusTransitions() async throws {
        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "pending",
            pageCount: 10,
            createdAt: Date()
        )

        try await repository.create(document)

        var fetched = try await repository.get(id: documentId)
        XCTAssertEqual(fetched?.status, "pending")

        try await repository.updateStatus(id: documentId, status: "processing")
        fetched = try await repository.get(id: documentId)
        XCTAssertEqual(fetched?.status, "processing")

        try await repository.updateStatus(id: documentId, status: "ready")
        fetched = try await repository.get(id: documentId)
        XCTAssertEqual(fetched?.status, "ready")

        try await repository.updateStatus(id: documentId, status: "failed")
        fetched = try await repository.get(id: documentId)
        XCTAssertEqual(fetched?.status, "failed")
    }

    func testListAllDocuments() async throws {
        let doc1 = DocumentRecord(
            id: UUID().uuidString,
            name: "doc1.pdf",
            type: "pdf",
            path: "/path/to/doc1.pdf",
            status: "ready",
            pageCount: 5,
            createdAt: Date().addingTimeInterval(-3600)
        )

        let doc2 = DocumentRecord(
            id: UUID().uuidString,
            name: "doc2.pdf",
            type: "pdf",
            path: "/path/to/doc2.pdf",
            status: "pending",
            pageCount: 10,
            createdAt: Date()
        )

        try await repository.create(doc1)
        try await repository.create(doc2)

        let all = try await repository.listAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].name, "doc2.pdf", "Should be ordered by createdAt DESC")
        XCTAssertEqual(all[1].name, "doc1.pdf")
    }

    func testGetNonExistentDocumentReturnsNil() async throws {
        let fetched = try await repository.get(id: "non-existent-id")
        XCTAssertNil(fetched)
    }

    func testGetChunksForNonExistentDocument() async throws {
        let chunks = try await repository.getChunks(documentId: "non-existent-id")
        XCTAssertEqual(chunks.count, 0)
    }
}
