import Foundation
import Testing
@testable import PhotoScanner

@Suite("Index Storage")
struct IndexStorageTests {
    @Test("磁盘索引快照可写可读")
    func diskBackedSnapshotRoundTrip() async throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = DiskBackedIndexStore(rootURL: rootURL)
        let snapshot = try makeSnapshot()

        try await store.saveSnapshot(snapshot)
        let loadedSnapshot = try await store.loadSnapshot()

        #expect(loadedSnapshot == snapshot)
    }

    @Test("mmap 精确检索返回最高分结果")
    func mmapBruteForceSearch() async throws {
        let rootURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = DiskBackedIndexStore(rootURL: rootURL)
        let vectorStore = MMapBruteForceVectorStore(indexStore: store)
        let snapshot = try makeSnapshot()

        try await vectorStore.replaceSnapshot(snapshot)
        let results = try await vectorStore.search(queryEmbedding: [1, 0, 0], topK: 2)

        #expect(results.count == 2)
        #expect(results.first?.assetLocalIdentifier == "asset-1")
        #expect(results.first?.score == 1)
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
