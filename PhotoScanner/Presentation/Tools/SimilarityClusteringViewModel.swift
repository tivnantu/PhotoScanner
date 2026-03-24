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
    case lenient = "宽容"
    case balanced = "平衡"
    case strict = "严格"
    
    var id: String { rawValue }
    
    var threshold: Float {
        switch self {
        case .lenient: return 0.70
        case .balanced: return 0.80
        case .strict: return 0.90
        }
    }
    
    var title: String { rawValue }
    
    var summary: String {
        switch self {
        case .lenient: return "更多相似图片被归为一组"
        case .balanced: return "推荐设置，平衡精度与召回"
        case .strict: return "仅非常相似的图片才会分组"
        }
    }
    
    var detail: String {
        "相似度阈值: \(Int(threshold * 100))%，最少 \(minClusterSize) 张组成一组"
    }
    
    var description: String {
        switch self {
        case .lenient: return "低阈值，更多分组"
        case .balanced: return "推荐设置"
        case .strict: return "高阈值，更少分组"
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
    private let indexEngine: IndexEngine
    
    // MARK: - 状态
    
    enum State {
        case idle
        case loading(progress: String)
        case loaded(clusters: [PhotoCluster])
        case error(String)
    }
    
    var state: State = .idle
    
    // 索引状态
    enum IndexState {
        case unknown
        case idle
        case building
        case paused
        case ready(count: Int)
        case partial(count: Int)
        case failed
        
        var canCluster: Bool {
            switch self {
            case .ready, .partial:
                return true
            default:
                return false
            }
        }
    }
    
    var indexState: IndexState = .unknown
    
    var indexStateDescription: (title: String, message: String) {
        switch indexState {
        case .idle, .unknown:
            return ("索引未开始", "请先分析照片以启用聚类功能")
        case .building:
            return ("索引构建中", "请等待索引完成后再进行聚类分析")
        case .paused:
            return ("索引已暂停", "请恢复索引并等待完成后再进行聚类分析")
        case .partial(let count):
            return ("索引部分就绪", "当前 \(count) 张照片已就绪，可以进行聚类，但建议等待全部完成")
        case .ready(let count):
            return ("索引就绪", "\(count) 张照片已就绪，可以进行聚类分析")
        case .failed:
            return ("索引失败", "索引构建失败，请检查错误并重新开始")
        }
    }
    
    var canCluster: Bool {
        indexState.canCluster
    }
    
    var isIndexFailed: Bool {
        if case .failed = indexState {
            return true
        }
        return false
    }
    
    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }
    
    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }
    
    var clusters: [PhotoCluster] {
        if case .loaded(let c) = state { return c }
        return []
    }
    
    var statistics: ClusteringStatistics? {
        guard !clusters.isEmpty else { return nil }
        let totalPhotos = clusters.reduce(0) { $0 + $1.assetIds.count }
        let avgSize = Double(totalPhotos) / Double(clusters.count)
        return ClusteringStatistics(
            clusterCount: clusters.count,
            groupedPhotoCount: totalPhotos,
            averageClusterSize: avgSize
        )
    }
    
    // 参数
    var selectedPreset: ClusteringPreset = .balanced
    
    // 缩略图缓存
    private var thumbnailCache: [String: UIImage] = [:]
    
    // MARK: - 初始化
    
    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.vectorStore = services.vectorStore
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
        self.indexEngine = services.indexEngine
    }
    
    // MARK: - 操作
    
    /// 检查索引状态
    func checkIndexStatus() async {
        let buildState = await indexEngine.loadCurrentState()
        
        switch buildState {
        case .idle:
            indexState = .idle
        case .preparing, .building:
            indexState = .building
        case .ready(let manifest):
            indexState = .ready(count: manifest.itemCount)
        case .failed:
            indexState = .failed
        }
    }
    
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
            
            // 2. 根据数据量选择聚类策略
            let threshold = selectedPreset.threshold
            let minPoints = selectedPreset.minClusterSize
            
            let clusters: [PhotoCluster]
            
            if entries.count > 500 {
                // 大数据量：使用 HNSW 加速（构建临时索引）
                state = .loading(progress: "构建加速索引...")
                clusters = try await dbscanClusterWithHNSW(entries, threshold: threshold, minPoints: minPoints)
            } else {
                // 小数据量：使用暴力搜索（避免索引构建开销）
                state = .loading(progress: "执行聚类...")
                clusters = try await dbscanClusterBruteForce(entries, threshold: threshold, minPoints: minPoints)
            }
            
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
    
    /// 按需加载缩略图（用于详情页）
    func loadThumbnail(for assetId: String) async -> UIImage? {
        // 先检查缓存
        if let cached = thumbnailCache[assetId] {
            return cached
        }
        
        // 从系统相册加载
        if let resource = await photoLibraryAssetProvider.previewResource(for: assetId),
           let data = resource.previewData,
           let image = UIImage(data: data) {
            thumbnailCache[assetId] = image
            return image
        }
        
        return nil
    }
    
    // MARK: - DBSCAN 算法（HNSW 加速版本）
    
    /// 使用 HNSW 索引加速的 DBSCAN 聚类
    /// 时间复杂度：O(n log n)，适用于大数据量场景
    private func dbscanClusterWithHNSW(
        _ entries: [IndexEntry],
        threshold: Float,
        minPoints: Int
    ) async throws -> [PhotoCluster] {
        let n = entries.count
        var labels = [Int?](repeating: nil, count: n)
        var clusterId = 0
        
        // 构建临时 HNSW 索引
        let hnswStore = HNSWVectorStore(embeddingDimension: 512)
        let snapshot = try IndexSnapshot(
            manifest: IndexManifest(
                modelID: "temp",
                modelVersion: "1",
                modelDisplayName: "temp",
                embeddingDimension: 512,
                imageSize: 224,
                contextLength: 52,
                modelFingerprint: "temp",
                resourceFingerprint: "temp",
                createdAt: Date(),
                updatedAt: Date(),
                itemCount: entries.count
            ),
            entries: entries
        )
        try await hnswStore.replaceSnapshot(snapshot)
        
        // 构建索引映射
        var idToIndex: [String: Int] = [:]
        for (i, entry) in entries.enumerated() {
            idToIndex[entry.assetLocalIdentifier] = i
        }
        
        state = .loading(progress: "执行 DBSCAN 聚类（HNSW 加速）...")
        
        // DBSCAN 主循环
        for i in 0..<n {
            // 已分类，跳过
            if labels[i] != nil { continue }
            
            // 使用 HNSW 查找邻居（O(log n) 复杂度）
            let neighbors = try await findNeighborsWithHNSW(
                entry: entries[i],
                hnswStore: hnswStore,
                idToIndex: idToIndex,
                threshold: threshold
            )
            
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
                
                // 使用 HNSW 查找邻居的邻居
                let jNeighbors = try await findNeighborsWithHNSW(
                    entry: entries[j],
                    hnswStore: hnswStore,
                    idToIndex: idToIndex,
                    threshold: threshold
                )
                
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
            // 计算聚类中心（与其他点平均相似度最高的点）
            let centerEntry = await findClusterCenterWithHNSW(
                entries: clusterEntries,
                hnswStore: hnswStore
            )
            
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
    
    /// 使用 HNSW 查找邻居
    private func findNeighborsWithHNSW(
        entry: IndexEntry,
        hnswStore: HNSWVectorStore,
        idToIndex: [String: Int],
        threshold: Float
    ) async throws -> [Int] {
        // 使用 HNSW 搜索 top-K 个最近邻
        let k = max(50, idToIndex.count / 10)
        
        let results = try await hnswStore.search(queryEmbedding: entry.embedding, topK: k)
        
        // 过滤出相似度大于阈值的邻居，并转换为索引
        var neighbors: [Int] = []
        for result in results {
            if result.score >= threshold {
                if let index = idToIndex[result.assetLocalIdentifier],
                   result.assetLocalIdentifier != entry.assetLocalIdentifier {
                    neighbors.append(index)
                }
            }
        }
        
        return neighbors
    }
    
    /// 使用 HNSW 查找聚类中心
    private func findClusterCenterWithHNSW(
        entries: [IndexEntry],
        hnswStore: HNSWVectorStore
    ) async -> IndexEntry {
        guard entries.count > 1 else { return entries[0] }
        
        var bestEntry = entries[0]
        var bestAvgSimilarity: Float = 0
        
        for entry in entries {
            // 使用 HNSW 搜索相似图片
            if let results = try? await hnswStore.search(queryEmbedding: entry.embedding, topK: entries.count) {
                // 计算与簇内其他图片的平均相似度
                let entryIds = Set(entries.map { $0.assetLocalIdentifier })
                let clusterResults = results.filter { entryIds.contains($0.assetLocalIdentifier) }
                
                if !clusterResults.isEmpty {
                    let avgSimilarity = clusterResults.reduce(0) { $0 + $1.score } / Float(clusterResults.count)
                    
                    if avgSimilarity > bestAvgSimilarity {
                        bestAvgSimilarity = avgSimilarity
                        bestEntry = entry
                    }
                }
            }
        }
        
        return bestEntry
    }
    
    // MARK: - DBSCAN 算法（暴力搜索版本）
    
    /// 使用暴力搜索的 DBSCAN 聚类
    /// 时间复杂度：O(n²)，适用于小数据量场景（< 500）
    private func dbscanClusterBruteForce(
        _ entries: [IndexEntry],
        threshold: Float,
        minPoints: Int
    ) async throws -> [PhotoCluster] {
        let n = entries.count
        var labels = [Int?](repeating: nil, count: n)
        var clusterId = 0
        
        // 构建索引映射
        var idToIndex: [String: Int] = [:]
        for (i, entry) in entries.enumerated() {
            idToIndex[entry.assetLocalIdentifier] = i
        }
        
        // DBSCAN 主循环
        for i in 0..<n {
            // 已分类，跳过
            if labels[i] != nil { continue }
            
            // 使用 vectorStore 查找邻居
            let neighbors = try await findNeighborsBruteForce(
                entry: entries[i],
                vectorStore: vectorStore,
                idToIndex: idToIndex,
                threshold: threshold
            )
            
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
                    labels[j] = clusterId
                }
                
                if labels[j] != nil { continue }
                
                labels[j] = clusterId
                
                let jNeighbors = try await findNeighborsBruteForce(
                    entry: entries[j],
                    vectorStore: vectorStore,
                    idToIndex: idToIndex,
                    threshold: threshold
                )
                
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
            // 简单选择第一个作为中心（小数据量场景）
            let centerEntry = clusterEntries[0]
            
            clusters.append(PhotoCluster(
                id: "\(clusterLabel)",
                assetIds: clusterEntries.map { $0.assetLocalIdentifier },
                centerAssetId: centerEntry.assetLocalIdentifier,
                similarityScore: threshold
            ))
        }
        
        return clusters.sorted { $0.assetIds.count > $1.assetIds.count }
    }
    
    /// 使用 vectorStore 暴力搜索查找邻居
    private func findNeighborsBruteForce(
        entry: IndexEntry,
        vectorStore: any VectorStore,
        idToIndex: [String: Int],
        threshold: Float
    ) async throws -> [Int] {
        // 搜索所有相似图片
        let results = try await vectorStore.search(queryEmbedding: entry.embedding, topK: idToIndex.count)
        
        // 过滤出相似度大于阈值的邻居
        var neighbors: [Int] = []
        for result in results {
            if result.score >= threshold {
                if let index = idToIndex[result.assetLocalIdentifier],
                   result.assetLocalIdentifier != entry.assetLocalIdentifier {
                    neighbors.append(index)
                }
            }
        }
        
        return neighbors
    }
    
    // MARK: - 旧的 DBSCAN 实现（保留作为参考，已弃用）
    
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
        // 加载聚类中心及其成员的缩略图
        for cluster in clusters {
            // 加载中心点
            if let centerAssetId = cluster.centerAssetId,
               thumbnailCache[centerAssetId] == nil {
                if let resource = await photoLibraryAssetProvider.previewResource(for: centerAssetId),
                   let data = resource.previewData,
                   let image = UIImage(data: data) {
                    thumbnailCache[centerAssetId] = image
                }
            }
            
            // 预加载前几个成员（用于详情页）
            for assetId in cluster.assetIds.prefix(10) {
                guard thumbnailCache[assetId] == nil else { continue }
                if let resource = await photoLibraryAssetProvider.previewResource(for: assetId),
                   let data = resource.previewData,
                   let image = UIImage(data: data) {
                    thumbnailCache[assetId] = image
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
