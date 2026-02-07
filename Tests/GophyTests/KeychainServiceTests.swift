import Testing
import Foundation
@testable import Gophy

@Suite("KeychainService Tests")
struct KeychainServiceTests {

    private let testServiceName = "com.gophy.api-keys.test.\(UUID().uuidString)"

    private func makeService() -> KeychainService {
        KeychainService(serviceName: testServiceName)
    }

    private func cleanup(_ service: KeychainService, providerIds: [String]) {
        for id in providerIds {
            try? service.delete(for: id)
        }
    }

    @Test("Save and retrieve an API key")
    func testSaveAndRetrieve() throws {
        let service = makeService()
        defer { cleanup(service, providerIds: ["openai"]) }

        try service.save(apiKey: "sk-test-key-12345", for: "openai")
        let retrieved = try service.retrieve(for: "openai")

        #expect(retrieved == "sk-test-key-12345")
    }

    @Test("Update an existing API key")
    func testUpdate() throws {
        let service = makeService()
        defer { cleanup(service, providerIds: ["openai"]) }

        try service.save(apiKey: "sk-old-key", for: "openai")
        try service.save(apiKey: "sk-new-key", for: "openai")

        let retrieved = try service.retrieve(for: "openai")
        #expect(retrieved == "sk-new-key")
    }

    @Test("Delete an API key")
    func testDelete() throws {
        let service = makeService()
        defer { cleanup(service, providerIds: ["openai"]) }

        try service.save(apiKey: "sk-test-key", for: "openai")
        try service.delete(for: "openai")

        let retrieved = try service.retrieve(for: "openai")
        #expect(retrieved == nil)
    }

    @Test("Retrieve returns nil for non-existent key")
    func testRetrieveNonExistent() throws {
        let service = makeService()

        let retrieved = try service.retrieve(for: "non-existent-provider")
        #expect(retrieved == nil)
    }

    @Test("List all stored provider IDs")
    func testListProviderIds() throws {
        let service = makeService()
        defer { cleanup(service, providerIds: ["openai", "anthropic", "groq"]) }

        try service.save(apiKey: "key1", for: "openai")
        try service.save(apiKey: "key2", for: "anthropic")
        try service.save(apiKey: "key3", for: "groq")

        let ids = try service.listProviderIds()
        #expect(ids.contains("openai"))
        #expect(ids.contains("anthropic"))
        #expect(ids.contains("groq"))
        #expect(ids.count >= 3)
    }

    @Test("Delete non-existent key does not throw")
    func testDeleteNonExistent() throws {
        let service = makeService()

        try service.delete(for: "non-existent-provider")
    }
}
