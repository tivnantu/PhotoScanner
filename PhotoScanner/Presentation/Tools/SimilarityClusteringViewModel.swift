//
// SimilarityClusteringViewModel.swift
// PhotoScanner
//
// 相似聚类功能的 ViewModel（使用 DBSCAN 算法）
//

import Foundation
import SwiftUI
import Photos
import OSLog

// MARK: - 阈值预设

enum ClusteringPreset: String, CaseIterable, Identifiable {
    case lenient = "宽容"
    case balanced = "平衡"
    case strict = "严格"

    var id: String { rawValue }

    /// 相似度阈值
    var threshold: Float {
        switch self {
        case .lenient: return 0.75
        case .balanced: return 0.80
        case .strict: return 0.85
        }
    }

    /// DBSCAN 最小邻居数（minPoints）
    var minPoints: Int {
        switch self {
        case .lenient: return 2   // 低阈值，容易成簇
        case .balanced: return 3  // 平衡
        case .strict: return 4    // 高阈值，需要更多邻居
        }
    }

    var title: String { rawValue }

    var summary: String {
        switch self {
        case .lenient: return "阈值\(Int(threshold * 100))%，邻居\(minPoints)，更多分组"
        case .balanced: return "阈值\(Int(threshold * 100))%，邻居\(minPoints)，推荐设置"
        case .strict: return "阈值\(Int(threshold * 100))%，邻居\(minPoints)，更精准"
        }
    }

    var detail: String {
        "相似度 ≥ \(Int(threshold * 100))%，至少 \(minPoints) 张相似"
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
        case .preparing:
            indexState = .building
        case .building(let progress):
            // 构建过程中，如果有已建立的部分索引，则可用
            if progress.completedCount > 0 {
                indexState = .partial(count: progress.completedCount)
            } else {
                indexState = .building
            }
        case .thermalPaused(let progress):
            // 热冷却暂停时，如果有已建立的部分索引，则可用
            if progress.completedCount > 0 {
                indexState = .partial(count: progress.completedCount)
            } else {
                indexState = .paused
            }
        case .ready(let manifest):
            indexState = .ready(count: manifest.itemCount)
        case .failed:
            indexState = .failed
        }
    }
    
    /// 执行聚类
    func performClustering() async {
        state = .loading(progress: "加载索引数据...")
        
        let totalStartTime = ContinuousClock.now
        
        do {
            // 1. 从 VectorStore 获取所有图片的 embedding
            let loadStartTime = ContinuousClock.now
            guard let snapshot = try await vectorStore.loadSnapshot() else {
                state = .error("索引为空，请先构建索引")
                return
            }
            let loadTime = loadStartTime.duration(to: .now)
            
            let entries = snapshot.entries
            guard !entries.isEmpty else {
                state = .error("没有可用的图片数据")
                return
            }
            
            // 2. 直接使用全局 HNSW 索引（vectorStore 已是 HNSWVectorStore）
            let threshold = selectedPreset.threshold
            let minPoints = selectedPreset.minPoints
            
            let clusters: [PhotoCluster]
            
            // 统一使用 HNSW 加速（全局索引已构建好）
            let clusterStartTime = ContinuousClock.now
            clusters = try await dbscanClusterWithGlobalHNSW(
                entries: entries,
                snapshot: snapshot,
                threshold: threshold,
                minPoints: minPoints
            )
            let clusterTime = clusterStartTime.duration(to: .now)
            
            // 3. 加载聚类中心的缩略图
            state = .loading(progress: "加载缩略图...")
            let thumbnailStartTime = ContinuousClock.now
            await loadThumbnails(for: clusters)
            let thumbnailTime = thumbnailStartTime.duration(to: .now)
            
            // 4. 更新状态
            state = .loaded(clusters: clusters)
            
            // 打印性能统计
            let totalTime = totalStartTime.duration(to: .now)
            Logger.ui.info("""
                [聚类统计] 总耗时: \(totalTime.components.seconds)s
                  - 加载索引: \(loadTime.components.seconds)s
                  - DBSCAN聚类: \(clusterTime.components.seconds)s
                  - 加载缩略图: \(thumbnailTime.components.seconds)s
                  - 聚类数: \(clusters.count), 总图片: \(clusters.reduce(0) { $0 + $1.assetIds.count })
                """)
        } catch {
            if error is CancellationError {
                state = .idle
            } else {
                state = .error(error.localizedDescription)
            }
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
    
    // MARK: - DBSCAN 算法（预计算邻居表优化版）
    
    /// 使用预计算邻居表的 DBSCAN 聚类
    /// 时间复杂度：O(n) 次搜索 + O(n) 次聚类遍历 = O(n)
    /// 空间复杂度：O(n * avgNeighbors)
    private func dbscanClusterWithGlobalHNSW(
        entries: [IndexEntry],
        snapshot: IndexSnapshot,
        threshold: Float,
        minPoints: Int
    ) async throws -> [PhotoCluster] {
        let n = entries.count
        var labels = [Int?](repeating: nil, count: n)
        var clusterId = 0
        
        // 构建索引映射
        var idToIndex: [String: Int] = [:]
        idToIndex.reserveCapacity(n)
        for (i, entry) in entries.enumerated() {
            idToIndex[entry.assetLocalIdentifier] = i
        }
        
        // ====== 阶段 1: 并行预计算所有邻居表 ======
        state = .loading(progress: "预计算邻居关系...")
        let precomputeStart = ContinuousClock.now
        
        let neighborTable = try await precomputeNeighborTable(
            entries: entries,
            idToIndex: idToIndex,
            threshold: threshold
        )
        
        let precomputeTime = precomputeStart.duration(to: .now)
        Logger.ui.info("[聚类统计] 预计算完成: \(precomputeTime.components.seconds)s, 邻居表大小: \(neighborTable.count)")
        
        // ====== 阶段 2: DBSCAN 聚类（纯内存操作，无需搜索） ======
        state = .loading(progress: "执行聚类...")
        let clusterStart = ContinuousClock.now
        
        // 进度跟踪
        var lastProgressUpdate = ContinuousClock.now
        let progressInterval = Duration.seconds(0.5)
        
        // DBSCAN 主循环
        for i in 0..<n {
            // 检查取消
            if Task.isCancelled {
                throw CancellationError()
            }
            
            // 已分类，跳过
            if labels[i] != nil { continue }
            
            // 更新进度
            let now = ContinuousClock.now
            if now - lastProgressUpdate > progressInterval {
                let progress = Double(i) / Double(n) * 100
                state = .loading(progress: String(format: "聚类分析中... %.0f%%", progress))
                lastProgressUpdate = now
            }
            
            // 直接从预计算表获取邻居（O(1) 查找）
            let neighbors = neighborTable[i]
            
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
                // 检查取消
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                let j = seedSet.removeFirst()
                
                if labels[j] == -1 {
                    labels[j] = clusterId // 噪声点转为边界点
                }
                
                if labels[j] != nil { continue }
                
                labels[j] = clusterId
                
                // 直接从预计算表获取邻居（O(1) 查找）
                let jNeighbors = neighborTable[j]
                
                if jNeighbors.count >= minPoints {
                    seedSet.formUnion(jNeighbors)
                }
            }
        }
        
        let clusterTime = clusterStart.duration(to: .now)
        Logger.ui.info("[聚类统计] 聚类完成: \(clusterTime.components.seconds)s")
        
        // 构建聚类结果
        var clusterMap: [Int: [IndexEntry]] = [:]
        
        for (i, label) in labels.enumerated() {
            guard let clusterLabel = label, clusterLabel > 0 else { continue }
            clusterMap[clusterLabel, default: []].append(entries[i])
        }
        
        // 转换为 PhotoCluster（简化中心选择）
        var clusters: [PhotoCluster] = []
        
        for (clusterLabel, clusterEntries) in clusterMap {
            // 简化：选择第一个作为中心（避免额外的搜索开销）
            let centerEntry = clusterEntries[0]
            
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
    
    /// 并行预计算所有点的邻居表
    /// - Returns: 索引 -> 邻居索引数组
    private func precomputeNeighborTable(
        entries: [IndexEntry],
        idToIndex: [String: Int],
        threshold: Float
    ) async throws -> [[Int]] {
        let n = entries.count
        let k = min(100, n)  // 每个 point 搜索 top-K
        
        // 并行搜索所有点
        let results = try await withThrowingTaskGroup(of: (Int, [Int]).self) { group in
            for i in 0..<n {
                group.addTask {
                    let searchResults = try await self.vectorStore.search(
                        queryEmbedding: entries[i].embedding,
                        topK: k
                    )
                    
                    // 过滤出邻居索引
                    var neighbors: [Int] = []
                    neighbors.reserveCapacity(min(k, 20))
                    
                    for result in searchResults {
                        if result.score >= threshold {
                            if let index = idToIndex[result.assetLocalIdentifier],
                               result.assetLocalIdentifier != entries[i].assetLocalIdentifier {
                                neighbors.append(index)
                            }
                        }
                    }
                    
                    return (i, neighbors)
                }
            }
            
            // 收集结果
            var table: [[Int]] = Array(repeating: [], count: n)
            for try await (index, neighbors) in group {
                table[index] = neighbors
            }
            return table
        }
        
        return results
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
}

// MARK: - 数据模型

struct PhotoCluster: Identifiable {
    let id: String
    let assetIds: [String]
    let centerAssetId: String?
    let similarityScore: Float
}
