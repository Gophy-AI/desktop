import XCTest
import Foundation
import GRDB
@testable import Gophy

final class VectorSearchServiceTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!
    var service: VectorSearchService!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyVectorSearchTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        service = VectorSearchService(database: database)
    }

    override func tearDown() async throws {
        service = nil
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testInsertAndSearchReturnsClosestMatch() async throws {
        let id1 = "chunk-1"
        let embedding1 = [Float](repeating: 1.0, count: 768)

        let id2 = "chunk-2"
        let embedding2 = [Float](repeating: 0.5, count: 768)

        let id3 = "chunk-3"
        let embedding3 = [Float](repeating: 0.0, count: 768)

        try await service.insert(id: id1, embedding: embedding1)
        try await service.insert(id: id2, embedding: embedding2)
        try await service.insert(id: id3, embedding: embedding3)

        let queryEmbedding = [Float](repeating: 0.9, count: 768)
        let results = try await service.search(query: queryEmbedding, limit: 3)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].id, id1, "ID with embedding closest to query should be first")
        XCTAssertLessThan(results[0].distance, results[1].distance, "Results should be ordered by distance ascending")
        XCTAssertLessThan(results[1].distance, results[2].distance)
    }

    func testCosineSimilarityRankingCorrect() async throws {
        let id1 = "chunk-1"
        var embedding1 = [Float](repeating: 0.0, count: 768)
        embedding1[0] = 1.0

        let id2 = "chunk-2"
        var embedding2 = [Float](repeating: 0.0, count: 768)
        embedding2[1] = 1.0

        try await service.insert(id: id1, embedding: embedding1)
        try await service.insert(id: id2, embedding: embedding2)

        var queryEmbedding = [Float](repeating: 0.0, count: 768)
        queryEmbedding[0] = 1.0

        let results = try await service.search(query: queryEmbedding, limit: 2)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, id1, "Should return exact match first")
        XCTAssertEqual(results[0].distance, 0.0, accuracy: 0.001, "Distance for identical vectors should be 0")
    }

    func testDeleteRemovesVectorFromResults() async throws {
        let id1 = "chunk-1"
        let embedding1 = [Float](repeating: 1.0, count: 768)

        let id2 = "chunk-2"
        let embedding2 = [Float](repeating: 0.5, count: 768)

        try await service.insert(id: id1, embedding: embedding1)
        try await service.insert(id: id2, embedding: embedding2)

        var count = try await service.count()
        XCTAssertEqual(count, 2)

        let queryEmbedding = [Float](repeating: 1.0, count: 768)
        var results = try await service.search(query: queryEmbedding, limit: 10)
        XCTAssertEqual(results.count, 2)

        try await service.delete(id: id1)

        count = try await service.count()
        XCTAssertEqual(count, 1)

        results = try await service.search(query: queryEmbedding, limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, id2)
    }

    func testCountReturnsCorrectNumber() async throws {
        var count = try await service.count()
        XCTAssertEqual(count, 0)

        let id1 = "chunk-1"
        let embedding1 = [Float](repeating: 1.0, count: 768)
        try await service.insert(id: id1, embedding: embedding1)

        count = try await service.count()
        XCTAssertEqual(count, 1)

        let id2 = "chunk-2"
        let embedding2 = [Float](repeating: 0.5, count: 768)
        try await service.insert(id: id2, embedding: embedding2)

        count = try await service.count()
        XCTAssertEqual(count, 2)

        try await service.delete(id: id1)
        count = try await service.count()
        XCTAssertEqual(count, 1)
    }

    func testSearchWithLimitReturnsAtMostLimitResults() async throws {
        for i in 0..<10 {
            let id = "chunk-\(i)"
            let embedding = [Float](repeating: Float(i) / 10.0, count: 768)
            try await service.insert(id: id, embedding: embedding)
        }

        let queryEmbedding = [Float](repeating: 0.5, count: 768)

        let results3 = try await service.search(query: queryEmbedding, limit: 3)
        XCTAssertEqual(results3.count, 3)

        let results5 = try await service.search(query: queryEmbedding, limit: 5)
        XCTAssertEqual(results5.count, 5)

        let results100 = try await service.search(query: queryEmbedding, limit: 100)
        XCTAssertEqual(results100.count, 10, "Should not return more than available")
    }

    func testSearchOnEmptyDatabaseReturnsEmpty() async throws {
        let queryEmbedding = [Float](repeating: 0.5, count: 768)
        let results = try await service.search(query: queryEmbedding, limit: 10)
        XCTAssertEqual(results.count, 0)
    }

    func testInsert100RandomVectorsSearchReturnsClosestMatch() async throws {
        var targetEmbedding = [Float](repeating: 0.0, count: 768)
        targetEmbedding[0] = 1.0
        targetEmbedding[1] = 1.0

        let targetId = "target-vector"
        try await service.insert(id: targetId, embedding: targetEmbedding)

        for i in 0..<100 {
            let id = "random-\(i)"
            var embedding = [Float](repeating: 0.0, count: 768)
            for j in 0..<768 {
                embedding[j] = Float.random(in: -1.0...1.0)
            }
            try await service.insert(id: id, embedding: embedding)
        }

        let results = try await service.search(query: targetEmbedding, limit: 1)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, targetId, "Closest match should be the identical target vector")
        XCTAssertEqual(results[0].distance, 0.0, accuracy: 0.001, "Distance to identical vector should be 0")
    }
}
