//
// VectorStore.swift
// PhotoScanner
//
// 向量检索边界。
// 当前阶段只约束最小能力：写入快照、读取快照、执行 Top-K 检索。
//

import Foundation

struct VectorSearchResult: Sendable, Equatable {
    let assetLocalIdentifier: String
    let assetFingerprint: String
    let score: Float
}

protocol VectorStore: Sendable {
    /// 从持久化恢复索引（如果有）
    func restoreIfAvailable() async throws -> Bool
    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws
    func loadSnapshot() async throws -> IndexSnapshot?
    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult]
    func getEmbedding(for assetId: String) async throws -> [Float]?
    func clear() async throws
    
    /// 批量搜索（性能优化，避免锁竞争）
    /// 默认实现：逐个调用 search()
    func batchSearch(queryEmbeddings: [[Float]], topK: Int) async throws -> [[VectorSearchResult]]
}

// MARK: - Default Implementation

extension VectorStore {
    /// 默认实现：逐个搜索
    func batchSearch(queryEmbeddings: [[Float]], topK: Int) async throws -> [[VectorSearchResult]] {
        var results: [[VectorSearchResult]] = []
        results.reserveCapacity(queryEmbeddings.count)
        for embedding in queryEmbeddings {
            results.append(try await search(queryEmbedding: embedding, topK: topK))
        }
        return results
    }
}
