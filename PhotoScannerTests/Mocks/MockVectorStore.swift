import Foundation
@testable import PhotoScanner

/// Mock VectorStore for testing
actor MockVectorStore {
    var mockEmbedding: [Float]?
    var mockResults: [VectorSearchResult] = []
    var getEmbeddingCallCount = 0
    var searchCallCount = 0
    
    nonisolated init() {}
    
    func getEmbedding(for assetId: String) async throws -> [Float]? {
        getEmbeddingCallCount += 1
        return mockEmbedding
    }
    
    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult] {
        searchCallCount += 1
        return mockResults
    }
    
    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws {}
    
    func loadSnapshot() async throws -> IndexSnapshot? { nil }
    
    func clear() async throws {}
}
