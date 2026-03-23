//
// HNSWVectorStore.swift
// PhotoScanner
//
// HNSW 向量存储实现
// 使用 HNSWIndex 提供近似最近邻搜索，O(log N) 复杂度
//

import Foundation
import OSLog

/// HNSW 向量存储
///
/// 特点：
/// - 搜索复杂度 O(log N)，适合大图库（10万+）
/// - 纯内存索引，启动时从快照构建
/// - 相比暴力搜索，牺牲少量精度换取速度
///
actor HNSWVectorStore: VectorStore {
    
    // MARK: - Properties
    
    /// HNSW 索引实例
    private var index: HNSWIndex
    
    /// 当前快照（用于持久化）
    private var currentSnapshot: IndexSnapshot?
    
    /// 模型维度
    private let embeddingDimension: Int
    
    /// HNSW 配置
    private let hnswConfig: HNSWIndex.Config
    
    // MARK: - Initialization
    
    init(embeddingDimension: Int = 512, config: HNSWIndex.Config? = nil) {
        self.embeddingDimension = embeddingDimension
        
        // 确保 config.dimension 与 embeddingDimension 一致
        if let config = config {
            self.hnswConfig = HNSWIndex.Config(
                maxConnections: config.maxConnections,
                maxConnectionsLayer0: config.maxConnectionsLayer0,
                efConstruction: config.efConstruction,
                efSearch: config.efSearch,
                dimension: embeddingDimension,
                distanceMetric: config.distanceMetric
            )
        } else {
            self.hnswConfig = HNSWIndex.Config(
                maxConnections: 16,
                maxConnectionsLayer0: 32,
                efConstruction: 200,
                efSearch: 100,
                dimension: embeddingDimension,
                distanceMetric: .cosine
            )
        }
        
        self.index = HNSWIndex(config: self.hnswConfig)
    }
    
    // MARK: - VectorStore Protocol
    
    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws {
        // 清空现有索引
        index.clear()
        
        // 从快照构建 HNSW 索引
        let entries = snapshot.entries
        var vectors: [(id: String, vector: [Float])] = []
        vectors.reserveCapacity(entries.count)
        
        for entry in entries {
            vectors.append((id: entry.assetLocalIdentifier, vector: entry.embedding))
        }
        
        // 批量插入
        index.insertBatch(vectors: vectors)
        currentSnapshot = snapshot
        
        Logger.index.info("HNSW 索引构建完成，条目数: \(entries.count)")
    }
    
    func loadSnapshot() async throws -> IndexSnapshot? {
        return currentSnapshot
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
        
        let startedAt = ContinuousClock.now
        
        // HNSW 搜索
        let results = index.search(vector: queryEmbedding, k: topK)
        
        let duration = startedAt.duration(to: .now)
        Logger.index.debug(
            "HNSW 检索完成，索引大小: \(self.index.count)，返回数: \(results.count)，耗时: \(duration.components.seconds)s"
        )
        
        // 转换结果格式
        guard let snapshot = currentSnapshot else {
            return []
        }
        
        return results.compactMap { result -> VectorSearchResult? in
            guard let entry = snapshot.entries.first(where: { $0.assetLocalIdentifier == result.externalId }) else {
                return nil
            }
            // HNSW 返回的是距离，转换为相似度分数
            let similarity = 1.0 - result.distance
            return VectorSearchResult(
                assetLocalIdentifier: entry.assetLocalIdentifier,
                assetFingerprint: entry.assetFingerprint,
                score: similarity
            )
        }
    }
    
    func getEmbedding(for assetId: String) async throws -> [Float]? {
        guard let snapshot = currentSnapshot else {
            return nil
        }
        return snapshot.entries.first(where: { $0.assetLocalIdentifier == assetId })?.embedding
    }
    
    func clear() async throws {
        index.clear()
        currentSnapshot = nil
        Logger.index.info("HNSWVectorStore 已清空")
    }
    
    // MARK: - Additional Methods
    
    /// 获取索引大小
    var count: Int {
        index.count
    }
    
    /// 检查索引是否为空
    var isEmpty: Bool {
        index.count == 0
    }
}
