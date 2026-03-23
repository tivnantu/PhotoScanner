//
// SimilarityClusteringViewModel.swift
// PhotoScanner
//
// 相似聚类功能的 ViewModel
//

import Foundation
import SwiftUI
import Photos

@MainActor
@Observable
final class SimilarityClusteringViewModel {
    
    // MARK: - 依赖
    
    private let embeddingService: EmbeddingService
    private let vectorStore: any VectorStore
    private let photoLibraryAssetProvider: PhotoLibraryAssetProvider
    
    // MARK: - 状态
    
    enum State {
        case idle
        case loading
        case loaded(clusters: [PhotoCluster])
        case error(String)
    }
    
    var state: State = .idle
    
    // 参数
    var similarityThreshold: Float = 0.8
    var minClusterSize: Int = 2
    
    // MARK: - 初始化
    
    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.vectorStore = services.vectorStore
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
    }
    
    // MARK: - 操作
    
    /// 执行聚类
    func performClustering() async {
        state = .loading
        
        do {
            // 1. 从 VectorStore 获取所有图片的 embedding
            guard let snapshot = try await vectorStore.loadSnapshot() else {
                state = .error("索引为空，请先构建索引")
                return
            }
            
            let entries = snapshot.entries
            guard !entries.isEmpty else {
                state = .error("没有可用的图片数据")
                return
            }
            
            // 2. 执行简单聚类（基于相似度阈值）
            let clusters = try await clusterEntries(entries)
            
            // 3. 过滤小簇
            let filteredClusters = clusters.filter { $0.assetIds.count >= minClusterSize }
            
            state = .loaded(clusters: filteredClusters)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// 重置状态
    func reset() {
        state = .idle
    }
    
    // MARK: - 聚类算法
    
    private func clusterEntries(_ entries: [IndexEntry]) async throws -> [PhotoCluster] {
        var visited = Set<String>()
        var clusters: [PhotoCluster] = []
        
        for entry in entries {
            // 如果已经归类，跳过
            if visited.contains(entry.assetLocalIdentifier) {
                continue
            }
            
            // 找到所有相似图片
            var clusterAssets = [entry.assetLocalIdentifier]
            visited.insert(entry.assetLocalIdentifier)
            
            for other in entries {
                if visited.contains(other.assetLocalIdentifier) {
                    continue
                }
                
                // 计算相似度
                let similarity = try cosineSimilarity(entry.embedding, other.embedding)
                
                if similarity >= similarityThreshold {
                    clusterAssets.append(other.assetLocalIdentifier)
                    visited.insert(other.assetLocalIdentifier)
                }
            }
            
            // 如果簇大小 >= minClusterSize，添加到结果
            if clusterAssets.count >= minClusterSize {
                clusters.append(PhotoCluster(
                    id: UUID().uuidString,
                    assetIds: clusterAssets,
                    similarityScore: similarityThreshold
                ))
            }
        }
        
        // 按簇大小排序
        return clusters.sorted { $0.assetIds.count > $1.assetIds.count }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) throws -> Float {
        guard a.count == b.count else {
            throw PSError.invalidModelOutput("向量维度不匹配")
        }
        
        let dot = zip(a, b).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(Float.zero) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(Float.zero) { $0 + $1 * $1 })
        
        guard normA > 0, normB > 0 else {
            return 0
        }
        
        return dot / (normA * normB)
    }
}

// MARK: - 数据模型

struct PhotoCluster: Identifiable {
    let id: String
    let assetIds: [String]
    let similarityScore: Float
}
