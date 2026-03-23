//
// BruteForceVectorStore.swift
// PhotoScanner
//
// 最小向量检索实现。
// 当前先用内存快照 + 暴力遍历满足小规模数据验证，不提前优化索引结构。
//

import Foundation
import OSLog

actor BruteForceVectorStore: VectorStore {

    private var snapshot: IndexSnapshot?

    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws {
        self.snapshot = snapshot
        Logger.index.info("VectorStore 已替换快照，条目数: \(snapshot.manifest.itemCount)")
    }

    func loadSnapshot() async throws -> IndexSnapshot? {
        snapshot
    }

    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult] {
        guard !queryEmbedding.isEmpty else {
            throw PSError.invalidInput("queryEmbedding 不能为空")
        }
        guard queryEmbedding.allSatisfy(\.isFinite) else {
            throw PSError.invalidModelOutput("queryEmbedding 包含非有限数值")
        }
        guard topK > 0 else {
            throw PSError.invalidInput("topK 必须大于 0")
        }
        guard let snapshot else {
            throw PSError.serviceNotReady(service: "VectorStore", reason: "索引快照尚未写入")
        }
        guard queryEmbedding.count == snapshot.manifest.embeddingDimension else {
            throw PSError.invalidModelOutput(
                "查询向量维度不匹配，期望 \(snapshot.manifest.embeddingDimension)，实际 \(queryEmbedding.count)"
            )
        }

        let limitedTopK = min(topK, snapshot.entries.count)
        guard limitedTopK > 0 else {
            Logger.index.info("VectorStore 检索完成，但当前索引为空")
            return []
        }

        let results = try snapshot.entries
            .map { entry in
                VectorSearchResult(
                    assetLocalIdentifier: entry.assetLocalIdentifier,
                    assetFingerprint: entry.assetFingerprint,
                    score: try dotProduct(queryEmbedding, entry.embedding)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.assetLocalIdentifier < rhs.assetLocalIdentifier
                }
                return lhs.score > rhs.score
            }

        let topResults = Array(results.prefix(limitedTopK))
        Logger.index.info("VectorStore 检索完成，候选数: \(snapshot.entries.count)，返回数: \(topResults.count)")
        return topResults
    }

    func clear() async throws {
        snapshot = nil
        Logger.index.info("VectorStore 已清空")
    }
    
    func getEmbedding(for assetId: String) async throws -> [Float]? {
        guard let snapshot else {
            return nil
        }
        
        return snapshot.entries.first { $0.assetLocalIdentifier == assetId }?.embedding
    }

    private func dotProduct(_ lhs: [Float], _ rhs: [Float]) throws -> Float {
        guard lhs.count == rhs.count else {
            throw PSError.invalidModelOutput(
                "向量检索维度不匹配：query=\(lhs.count), candidate=\(rhs.count)"
            )
        }

        return zip(lhs, rhs).reduce(Float.zero) { partial, pair in
            partial + pair.0 * pair.1
        }
    }
}
