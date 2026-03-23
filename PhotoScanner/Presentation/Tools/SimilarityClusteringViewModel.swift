//
// SimilarityClusteringViewModel.swift
// PhotoScanner
//
// 相似聚类功能的 ViewModel（使用 DBSCAN 算法）
//

import Foundation
import SwiftUI
import Photos

// MARK: - 阈值预设

enum ClusteringPreset: String, CaseIterable, Identifiable {
    case moreLenient = "更宽容"
    case lenient = "较宽容"
    case balanced = "平衡"
    case strict = "较严格"
    case moreStrict = "更严格"
    
    var id: String { rawValue }
    
    var threshold: Float {
        switch self {
        case .moreLenient: return 0.70
        case .lenient: return 0.75
        case .balanced: return 0.80
        case .strict: return 0.85
        case .moreStrict: return 0.90
        }
    }
    
    var description: String {
        switch self {
        case .moreLenient: return "低阈值，更多分组"
        case .lenient: return "较低阈值"
        case .balanced: return "推荐设置"
        case .strict: return "较高阈值"
        case .moreStrict: return "高阈值，更少分组"
        }
    }
    
    var minClusterSize: Int {
        return 2
    }
}

// MARK: - ViewModel

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
        case loading(progress: String)
        case loaded(clusters: [PhotoCluster])
        case error(String)
    }
    
    var state: State = .idle
    
    // 参数
    var selectedPreset: ClusteringPreset = .balanced
    
    // 缩略图缓存
    private var thumbnailCache: [String: UIImage] = [:]
    
    // MARK: - 初始化
    
    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.vectorStore = services.vectorStore
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
    }
    
    // MARK: - 操作
    
    /// 执行聚类
    func performClustering() async {
        state = .loading(progress: "加载索引数据...")
        
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
            
            // 2. 执行 DBSCAN 聚类
            let threshold = selectedPreset.threshold
            let minPoints = selectedPreset.minClusterSize
            
            let clusters = try await dbscanCluster(entries, threshold: threshold, minPoints: minPoints)
            
            // 3. 加载聚类中心的缩略图
            state = .loading(progress: "加载缩略图...")
            await loadThumbnails(for: clusters)
            
            // 4. 更新状态
            state = .loaded(clusters: clusters)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// 重置状态
    func reset() {
        state = .idle
        thumbnailCache.removeAll()
    }
    
    /// 获取缩略图
    func thumbnail(for assetId: String) -> UIImage? {
        return thumbnailCache[assetId]
    }
    
    // MARK: - DBSCAN 算法
    
    private func dbscanCluster(
        _ entries: [IndexEntry],
        threshold: Float,
        minPoints: Int
    ) async throws -> [PhotoCluster] {
        let n = entries.count
        var labels = [Int?](repeating: nil, count: n)
        var clusterId = 0
        
        // 预计算距离矩阵（上三角）
        state = .loading(progress: "计算相似度矩阵...")
        let distanceMatrix = try await computeDistanceMatrix(entries)
        
        state = .loading(progress: "执行 DBSCAN 聚类...")
        
        for i in 0..<n {
            // 已分类，跳过
            if labels[i] != nil { continue }
            
            // 查找邻域
            let neighbors = findNeighbors(i: i, distanceMatrix: distanceMatrix, threshold: threshold, n: n)
            
            // 核心点判定
            if neighbors.count < minPoints {
                labels[i] = -1 // 噪声点
                continue
            }
            
            // 扩展簇
            clusterId += 1
            labels[i] = clusterId
            
            var seedSet = Set(neighbors)
            seedSet.remove(i)
            
            while !seedSet.isEmpty {
                let j = seedSet.removeFirst()
                
                if labels[j] == -1 {
                    labels[j] = clusterId // 噪声点转为边界点
                }
                
                if labels[j] != nil { continue }
                
                labels[j] = clusterId
                
                let jNeighbors = findNeighbors(i: j, distanceMatrix: distanceMatrix, threshold: threshold, n: n)
                
                if jNeighbors.count >= minPoints {
                    seedSet.formUnion(jNeighbors)
                }
            }
        }
        
        // 构建聚类结果
        var clusterMap: [Int: [IndexEntry]] = [:]
        
        for (i, label) in labels.enumerated() {
            guard let clusterLabel = label, clusterLabel > 0 else { continue }
            clusterMap[clusterLabel, default: []].append(entries[i])
        }
        
        // 转换为 PhotoCluster
        var clusters: [PhotoCluster] = []
        
        for (clusterLabel, clusterEntries) in clusterMap {
            // 找到聚类中心（与其他点平均距离最小的点）
            let centerEntry = findClusterCenter(entries: clusterEntries, distanceMatrix: distanceMatrix, allEntries: entries)
            
            clusters.append(PhotoCluster(
                id: "\(clusterLabel)",
                assetIds: clusterEntries.map { $0.assetLocalIdentifier },
                centerAssetId: centerEntry.assetLocalIdentifier,
                similarityScore: threshold
            ))
        }
        
        // 按簇大小排序
        return clusters.sorted { $0.assetIds.count > $1.assetIds.count }
    }
    
    /// 计算距离矩阵（相似度）
    private func computeDistanceMatrix(_ entries: [IndexEntry]) async throws -> [[Float]] {
        let n = entries.count
        var matrix = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        
        // 只计算上三角
        for i in 0..<n {
            matrix[i][i] = 1.0 // 自己与自己的相似度为 1
            
            for j in (i+1)..<n {
                let similarity = try cosineSimilarity(entries[i].embedding, entries[j].embedding)
                matrix[i][j] = similarity
                matrix[j][i] = similarity // 对称
            }
        }
        
        return matrix
    }
    
    /// 查找邻域
    private func findNeighbors(i: Int, distanceMatrix: [[Float]], threshold: Float, n: Int) -> [Int] {
        var neighbors: [Int] = []
        
        for j in 0..<n {
            if i != j && distanceMatrix[i][j] >= threshold {
                neighbors.append(j)
            }
        }
        
        return neighbors
    }
    
    /// 找到聚类中心
    private func findClusterCenter(
        entries: [IndexEntry],
        distanceMatrix: [[Float]],
        allEntries: [IndexEntry]
    ) -> IndexEntry {
        guard entries.count > 1 else { return entries[0] }
        
        // 构建索引映射
        var indexMap: [String: Int] = [:]
        for (i, entry) in allEntries.enumerated() {
            indexMap[entry.assetLocalIdentifier] = i
        }
        
        var bestEntry = entries[0]
        var bestAvgDistance = Float.infinity
        
        for entry in entries {
            guard let i = indexMap[entry.assetLocalIdentifier] else { continue }
            
            var totalDistance: Float = 0
            var count = 0
            
            for other in entries {
                guard let j = indexMap[other.assetLocalIdentifier], i != j else { continue }
                totalDistance += distanceMatrix[i][j]
                count += 1
            }
            
            if count > 0 {
                let avgDistance = totalDistance / Float(count)
                if avgDistance > bestAvgDistance { // 相似度越高越好
                    bestAvgDistance = avgDistance
                    bestEntry = entry
                }
            }
        }
        
        return bestEntry
    }
    
    /// 加载缩略图
    private func loadThumbnails(for clusters: [PhotoCluster]) async {
        // 只加载聚类中心的缩略图
        for cluster in clusters {
            if let centerAssetId = cluster.centerAssetId,
               thumbnailCache[centerAssetId] == nil {
                if let resource = await photoLibraryAssetProvider.previewResource(for: centerAssetId),
                   let data = resource.previewData,
                   let image = UIImage(data: data) {
                    thumbnailCache[centerAssetId] = image
                }
            }
        }
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
    let centerAssetId: String?
    let similarityScore: Float
}
