import Foundation
import PDFKit
import AppKit

public protocol OCREngineProviding: Sendable {
    func extractText(from fileURL: URL) async throws -> String
    func extractText(from cgImage: CGImage) async throws -> String
}

public protocol EmbeddingPipelineProviding: Sendable {
    func indexDocument(documentId: String) async throws
}

extension EmbeddingPipeline: EmbeddingPipelineProviding {}

/// Adapter that wraps a VisionProvider as an OCREngineProviding for DocumentProcessor
private final class VisionProviderOCRAdapter: OCREngineProviding, @unchecked Sendable {
    private let provider: any VisionProvider

    init(provider: any VisionProvider) {
        self.provider = provider
    }

    func extractText(from fileURL: URL) async throws -> String {
        guard let image = NSImage(contentsOf: fileURL),
              let data = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: data),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw DocumentProcessingError.ocrFailed("Failed to load image from file")
        }
        return try await provider.extractText(from: jpegData, prompt: "Extract all text from this image. Return only the extracted text with no additional commentary.")
    }

    func extractText(from cgImage: CGImage) async throws -> String {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw DocumentProcessingError.ocrFailed("Failed to convert image to JPEG")
        }
        return try await provider.extractText(from: jpegData, prompt: "Extract all text from this image. Return only the extracted text with no additional commentary.")
    }
}

public final class DocumentProcessor: Sendable {
    private let documentRepository: DocumentRepository
    private let ocrEngine: any OCREngineProviding
    private let embeddingPipeline: any EmbeddingPipelineProviding
    private let chunkSize: Int
    private let chunkOverlap: Int

    public init(
        documentRepository: DocumentRepository,
        ocrEngine: any OCREngineProviding,
        embeddingPipeline: any EmbeddingPipelineProviding,
        chunkSize: Int = 500,
        chunkOverlap: Int = 100
    ) {
        precondition(chunkSize > chunkOverlap, "chunkSize must be greater than chunkOverlap to avoid infinite loops")
        self.documentRepository = documentRepository
        self.ocrEngine = ocrEngine
        self.embeddingPipeline = embeddingPipeline
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
    }

    /// Initialize with a VisionProvider for cloud-based OCR
    public init(
        documentRepository: DocumentRepository,
        visionProvider: any VisionProvider,
        embeddingPipeline: any EmbeddingPipelineProviding,
        chunkSize: Int = 500,
        chunkOverlap: Int = 100
    ) {
        precondition(chunkSize > chunkOverlap, "chunkSize must be greater than chunkOverlap to avoid infinite loops")
        self.documentRepository = documentRepository
        self.ocrEngine = VisionProviderOCRAdapter(provider: visionProvider)
        self.embeddingPipeline = embeddingPipeline
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
    }

    public func process(fileURL: URL) async throws -> DocumentRecord {
        let fileExtension = fileURL.pathExtension.lowercased()
        let fileName = fileURL.lastPathComponent

        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: fileName,
            type: fileExtension,
            path: fileURL.path,
            status: "pending",
            pageCount: 0,
            createdAt: Date()
        )

        try await documentRepository.create(document)
        try await documentRepository.updateStatus(id: documentId, status: "processing")

        do {
            let (text, pageCount, pageMap) = try await extractText(from: fileURL, type: fileExtension)

            let updatedDocument = DocumentRecord(
                id: documentId,
                name: fileName,
                type: fileExtension,
                path: fileURL.path,
                status: "ready",
                pageCount: pageCount,
                createdAt: document.createdAt
            )

            let chunks = createChunks(from: text, documentId: documentId, pageCount: pageCount, pageMap: pageMap)
            for chunk in chunks {
                try await documentRepository.addChunk(chunk)
            }

            try await documentRepository.updateStatus(id: documentId, status: "ready")

            try await embeddingPipeline.indexDocument(documentId: documentId)

            return updatedDocument
        } catch {
            try await documentRepository.updateStatus(id: documentId, status: "failed")
            throw error
        }
    }

    private func extractText(from fileURL: URL, type: String) async throws -> (String, Int, [Int: Int]) {
        switch type {
        case "txt", "md":
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return (text, 1, [0: 1])

        case "pdf":
            return try await extractTextFromPDF(fileURL)

        case "png", "jpg", "jpeg":
            let text = try await ocrEngine.extractText(from: fileURL)
            return (text, 1, [0: 1])

        default:
            throw DocumentProcessingError.unsupportedFormat(type)
        }
    }

    private func extractTextFromPDF(_ fileURL: URL) async throws -> (String, Int, [Int: Int]) {
        guard let pdfDocument = PDFDocument(url: fileURL) else {
            throw DocumentProcessingError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        var fullText = ""
        var pageMap: [Int: Int] = [:]

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }
            let startPosition = fullText.count
            fullText += pageText + "\n"
            pageMap[startPosition] = pageIndex + 1
        }

        // If no text was extracted (scanned PDF), fall back to OCR
        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await extractTextFromPDFViaOCR(pdfDocument, pageCount: pageCount)
        }

        return (fullText, pageCount, pageMap)
    }

    private func extractTextFromPDFViaOCR(_ pdfDocument: PDFDocument, pageCount: Int) async throws -> (String, Int, [Int: Int]) {
        var fullText = ""
        var pageMap: [Int: Int] = [:]

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }

            // Render page to image at reasonable DPI (144 DPI for good OCR quality)
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

            guard let cgImage = renderPageToCGImage(page: page, size: size) else {
                continue
            }

            let startPosition = fullText.count
            let pageText = try await ocrEngine.extractText(from: cgImage)
            fullText += pageText + "\n"
            pageMap[startPosition] = pageIndex + 1
        }

        return (fullText, pageCount, pageMap)
    }

    private func renderPageToCGImage(page: PDFPage, size: CGSize) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Fill white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        // Scale and render the PDF page
        context.scaleBy(x: size.width / pageRect.width, y: size.height / pageRect.height)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    private func createChunks(from text: String, documentId: String, pageCount: Int, pageMap: [Int: Int]) -> [DocumentChunkRecord] {
        guard !text.isEmpty else {
            return []
        }

        var chunks: [DocumentChunkRecord] = []
        var currentIndex = text.startIndex
        var chunkIndex = 0

        while currentIndex < text.endIndex {
            let remainingDistance = text.distance(from: currentIndex, to: text.endIndex)
            let currentChunkSize = min(chunkSize, remainingDistance)

            let endIndex = text.index(currentIndex, offsetBy: currentChunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = String(text[currentIndex..<endIndex])

            let chunkPosition = text.distance(from: text.startIndex, to: currentIndex)
            let pageNumber = calculatePageNumber(position: chunkPosition, totalPages: pageCount, pageMap: pageMap)

            let chunk = DocumentChunkRecord(
                id: UUID().uuidString,
                documentId: documentId,
                content: chunkText,
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                createdAt: Date()
            )
            chunks.append(chunk)

            if endIndex == text.endIndex {
                break
            }

            let overlapSize = min(chunkOverlap, currentChunkSize)
            let nextStartIndex = text.index(currentIndex, offsetBy: currentChunkSize - overlapSize, limitedBy: text.endIndex) ?? text.endIndex

            if nextStartIndex >= text.endIndex {
                break
            }

            currentIndex = nextStartIndex
            chunkIndex += 1
        }

        return chunks
    }

    private func calculatePageNumber(position: Int, totalPages: Int, pageMap: [Int: Int]) -> Int {
        guard totalPages > 1 else {
            return 1
        }

        // Find the page number by looking up the largest position <= current position
        let sortedPositions = pageMap.keys.sorted()
        for i in stride(from: sortedPositions.count - 1, through: 0, by: -1) {
            let pos = sortedPositions[i]
            if position >= pos {
                return pageMap[pos] ?? 1
            }
        }

        return 1
    }
}

public enum DocumentProcessingError: Error, Sendable {
    case unsupportedFormat(String)
    case invalidPDF
    case ocrFailed(String)
}

extension OCREngine: OCREngineProviding {
    public func extractText(from fileURL: URL) async throws -> String {
        guard let image = NSImage(contentsOf: fileURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocumentProcessingError.ocrFailed("Failed to load image from file")
        }

        return try await extractText(from: cgImage)
    }
}
