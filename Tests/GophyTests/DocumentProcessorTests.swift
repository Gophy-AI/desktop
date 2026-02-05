import XCTest
import Foundation
import GRDB
import PDFKit
import AppKit
@testable import Gophy

final class MockOCREngineProvider: OCREngineProviding, @unchecked Sendable {
    var extractTextCalled = false
    var textToReturn = "Extracted text from image"

    func extractText(from fileURL: URL) async throws -> String {
        extractTextCalled = true
        return textToReturn
    }

    func extractText(from cgImage: CGImage) async throws -> String {
        extractTextCalled = true
        return textToReturn
    }
}

final class MockEmbeddingPipelineProvider: EmbeddingPipelineProviding, @unchecked Sendable {
    var indexDocumentCalled = false
    var lastIndexedDocumentId: String?

    func indexDocument(documentId: String) async throws {
        indexDocumentCalled = true
        lastIndexedDocumentId = documentId
    }
}

final class DocumentProcessorTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!
    var documentRepository: DocumentRepository!
    var mockOCR: MockOCREngineProvider!
    var mockPipeline: MockEmbeddingPipelineProvider!
    var processor: DocumentProcessor!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyDocumentProcessorTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        documentRepository = DocumentRepository(database: database)
        mockOCR = MockOCREngineProvider()
        mockPipeline = MockEmbeddingPipelineProvider()
        processor = DocumentProcessor(
            documentRepository: documentRepository,
            ocrEngine: mockOCR,
            embeddingPipeline: mockPipeline
        )
    }

    override func tearDown() async throws {
        processor = nil
        mockPipeline = nil
        mockOCR = nil
        documentRepository = nil
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testProcessTextFileCreatesChunksDirectly() async throws {
        let content = """
        This is a test plain text file.
        It contains multiple lines of text that should be chunked appropriately.
        The chunking algorithm should respect the 500 character limit with 100 character overlap.
        Each chunk should be stored in the database.
        """
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "txt")
        XCTAssertEqual(document.name, "test.txt")

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertGreaterThan(chunks.count, 0, "Should create at least one chunk")
        XCTAssertFalse(mockOCR.extractTextCalled, "Should not call OCR for text files")
        XCTAssertTrue(mockPipeline.indexDocumentCalled, "Should index the document")
    }

    func testProcessMarkdownFileCreatesChunks() async throws {
        let content = """
        # Markdown Document

        This is a markdown file with various sections.

        ## Section 1
        Some content here.

        ## Section 2
        More content that will be chunked.
        """
        let testFile = tempDirectory.appendingPathComponent("test.md")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "md")

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertGreaterThan(chunks.count, 0)
        XCTAssertFalse(mockOCR.extractTextCalled)
    }

    func testChunkingRespects500CharAnd100Overlap() async throws {
        let longText = String(repeating: "A", count: 1200)
        let testFile = tempDirectory.appendingPathComponent("long.txt")
        try longText.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        let chunks = try await documentRepository.getChunks(documentId: document.id)

        XCTAssertGreaterThanOrEqual(chunks.count, 2, "Long text should be split into multiple chunks")

        for (index, chunk) in chunks.enumerated() {
            XCTAssertLessThanOrEqual(chunk.content.count, 500, "Chunk \(index) exceeds 500 characters")
            XCTAssertEqual(chunk.chunkIndex, index)
        }

        if chunks.count > 1 {
            let firstChunkEnd = chunks[0].content.suffix(100)
            let secondChunkStart = chunks[1].content.prefix(100)
            XCTAssertEqual(String(firstChunkEnd), String(secondChunkStart), "Should have 100 character overlap")
        }
    }

    func testDocumentStatusTransitionsThroughProcessingLifecycle() async throws {
        let content = "Simple test content"
        let testFile = tempDirectory.appendingPathComponent("status-test.txt")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        let retrievedDocument = try await documentRepository.get(id: document.id)
        XCTAssertEqual(retrievedDocument?.status, "ready")
    }

    func testFailedProcessingSetsStatusToFailed() async throws {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt")

        do {
            _ = try await processor.process(fileURL: nonExistentFile)
            XCTFail("Should throw error for non-existent file")
        } catch {
            XCTAssertTrue(error is DocumentProcessingError || error is CocoaError)
        }

        // Verify that a document was created and its status is set to "failed"
        let allDocuments = try await documentRepository.listAll()
        XCTAssertEqual(allDocuments.count, 1, "Should have created one document record")
        XCTAssertEqual(allDocuments.first?.status, "failed", "Document status should be 'failed' after processing failure")
    }

    func testProcessPNGImageUsesOCR() async throws {
        mockOCR.textToReturn = "Text extracted from PNG image via OCR"

        let testFile = tempDirectory.appendingPathComponent("test.png")
        let imageData = createDummyImageData()
        try imageData.write(to: testFile)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "png")
        XCTAssertTrue(mockOCR.extractTextCalled, "Should call OCR for PNG files")

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertGreaterThan(chunks.count, 0)
        XCTAssertTrue(chunks[0].content.contains("Text extracted from PNG image"))
    }

    func testProcessJPGImageUsesOCR() async throws {
        mockOCR.textToReturn = "Text extracted from JPG image via OCR"

        let testFile = tempDirectory.appendingPathComponent("test.jpg")
        let imageData = createDummyImageData()
        try imageData.write(to: testFile)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "jpg")
        XCTAssertTrue(mockOCR.extractTextCalled, "Should call OCR for JPG files")

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertGreaterThan(chunks.count, 0)
    }

    func testProcessPDFWithPDFKit() async throws {
        let pdfData = createDummyPDFData()
        let testFile = tempDirectory.appendingPathComponent("test.pdf")
        try pdfData.write(to: testFile)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "pdf")
        XCTAssertGreaterThan(document.pageCount, 0, "PDF should have page count")
    }

    func testScannedPDFFallsBackToOCR() async throws {
        mockOCR.textToReturn = "Text extracted via OCR from scanned PDF"

        // Create a PDF with no text content (simulates a scanned document)
        let pdfData = createDummyPDFData()
        let testFile = tempDirectory.appendingPathComponent("scanned.pdf")
        try pdfData.write(to: testFile)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertEqual(document.status, "ready")
        XCTAssertEqual(document.type, "pdf")
        XCTAssertTrue(mockOCR.extractTextCalled, "Should call OCR for scanned PDF with no extractable text")

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertGreaterThan(chunks.count, 0)
        XCTAssertTrue(chunks[0].content.contains("Text extracted via OCR"))
    }

    func testSmallTextCreatesOneChunk() async throws {
        let content = "Small content"
        let testFile = tempDirectory.appendingPathComponent("small.txt")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        let chunks = try await documentRepository.getChunks(documentId: document.id)
        XCTAssertEqual(chunks.count, 1, "Small text should create exactly one chunk")
        XCTAssertEqual(chunks[0].content, content)
        XCTAssertEqual(chunks[0].chunkIndex, 0)
    }

    func testDocumentIsIndexedAfterProcessing() async throws {
        let content = "Content to be indexed"
        let testFile = tempDirectory.appendingPathComponent("indexed.txt")
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        XCTAssertTrue(mockPipeline.indexDocumentCalled)
        XCTAssertEqual(mockPipeline.lastIndexedDocumentId, document.id)
    }

    func testMultipleChunksHaveCorrectPageNumbers() async throws {
        let longText = String(repeating: "B", count: 1500)
        let testFile = tempDirectory.appendingPathComponent("multipage.txt")
        try longText.write(to: testFile, atomically: true, encoding: .utf8)

        let document = try await processor.process(fileURL: testFile)

        let chunks = try await documentRepository.getChunks(documentId: document.id)

        for chunk in chunks {
            XCTAssertGreaterThan(chunk.pageNumber, 0, "All chunks should have valid page numbers")
        }
    }

    private func createDummyImageData() -> Data {
        let size = CGSize(width: 100, height: 100)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return pngData
    }

    private func createDummyPDFData() -> Data {
        let pdfData = NSMutableData()
        let pdfConsumer = CGDataConsumer(data: pdfData)!

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)!

        pdfContext.beginPDFPage(nil)
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return pdfData as Data
    }
}
