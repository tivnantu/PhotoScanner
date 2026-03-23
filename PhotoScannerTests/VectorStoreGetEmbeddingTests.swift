import Foundation
import Testing
@testable import PhotoScanner

@Suite("VectorStore getEmbedding 测试")
struct VectorStoreGetEmbeddingTests {
    
    @Test("缓存存在时返回 embedding")
    func getEmbedding_cachedAsset_returnsEmbedding() async throws {
        // Given
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        
        let store = DiskBackedIndexStore(rootURL: rootURL)
        let vectorStore = MMapBruteForceVectorStore(indexStore: store)
        let snapshot = try makeSnapshot()
        
        try await vectorStore.replaceSnapshot(snapshot)
        
        // When
        let result = try await vectorStore.getEmbedding(for: "asset-1")
        
        // Then
        #expect(result != nil)
        #expect(result?.count == 3)
        #expect(result?.first == 1)
    }
    
    @Test("缓存不存在时返回 nil")
    func getEmbedding_nonExistingAsset_returnsNil() async throws {
        // Given
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        
        let store = DiskBackedIndexStore(rootURL: rootURL)
        let vectorStore = MMapBruteForceVectorStore(indexStore: store)
        let snapshot = try makeSnapshot()
        
        try await vectorStore.replaceSnapshot(snapshot)
        
        // When
        let result = try await vectorStore.getEmbedding(for: "non-existing-asset")
        
        // Then
        #expect(result == nil)
    }
    
    @Test("getEmbedding 性能 < 5ms")
    func getEmbedding_performance() async throws {
        // Given
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        
        let store = DiskBackedIndexStore(rootURL: rootURL)
        let vectorStore = MMapBruteForceVectorStore(indexStore: store)
        let snapshot = try makeSnapshot()
        
        try await vectorStore.replaceSnapshot(snapshot)
        
        // When
        let start = Date()
        for _ in 0..<100 {
            _ = try await vectorStore.getEmbedding(for: "asset-1")
        }
        let duration = Date().timeIntervalSince(start) * 1000 / 100 // 平均每次
        
        // Then
        #expect(duration < 5, "平均耗时 \(duration)ms，超过 5ms 阈值")
    }
    
    private func makeSnapshot() throws -> IndexSnapshot {
        let fixedDate = Date(timeIntervalSince1970: 1_710_000_000)
        let descriptor = ModelDescriptor(
            id: "test-model",
            version: "1.0.0",
            embeddingDimension: 3,
            imageSize: 224,
            contextLength: 52,
            displayName: "Test Model"
        )
        let manifest = try IndexManifest(
            modelDescriptor: descriptor,
            modelFingerprint: "model-fingerprint",
            resourceFingerprint: "resource-fingerprint",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            itemCount: 2
        )
        let first = try IndexEntry(
            assetLocalIdentifier: "asset-1",
            assetFingerprint: "fp-1",
            embedding: [1, 0, 0],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let second = try IndexEntry(
            assetLocalIdentifier: "asset-2",
            assetFingerprint: "fp-2",
            embedding: [0.5, 0.5, 0],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        return try IndexSnapshot(manifest: manifest, entries: [first, second])
    }
    
    private func makeTemporaryDirectory() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
