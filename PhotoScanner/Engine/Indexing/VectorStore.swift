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
    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws
    func loadSnapshot() async throws -> IndexSnapshot?
    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult]
    func getEmbedding(for assetId: String) async throws -> [Float]?
    func clear() async throws
}
