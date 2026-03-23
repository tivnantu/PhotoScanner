//
// HNSWIndex.swift
// PhotoScanner
//
// HNSW 向量索引
// 纯 Swift 实现的 Hierarchical Navigable Small World 索引
//

import Foundation
import Accelerate
import OSLog

/// HNSW 向量索引
///
/// 纯 Swift 实现的 Hierarchical Navigable Small World 索引：
/// - 近似最近邻搜索，O(log N) 复杂度
/// - 支持增量插入
/// - 线程安全（使用 NSLock）
///
/// 参考: https://arxiv.org/abs/1603.09320
///
/// ## 性能特点
/// - 搜索复杂度: O(log N)
/// - 空间开销: 约 20% 额外连接存储
/// - 适用于 10万+ 图片的大图库场景
///
/// ## 使用示例
/// ```swift
/// let index = HNSWIndex(config: .default)
///
/// // 批量插入
/// index.insertBatch(vectors: [
///     ("photo1", embedding1),
///     ("photo2", embedding2)
/// ])
///
/// // 搜索最近邻
/// let results = index.search(vector: queryVector, k: 20)
/// for result in results {
///     print("id: \(result.externalId), distance: \(result.distance)")
/// }
/// ```
///
/// ## 线程安全说明
/// 使用 `@unchecked Sendable` 是安全的，因为：
/// - 所有可变状态都是 `private`
/// - 所有公开方法都通过 `lock.lock()` / `lock.unlock()` 保护
/// - `lock` 属性本身是 `let`，不可重新赋值
final class HNSWIndex: @unchecked Sendable {

    // MARK: - Types

    /// 节点 ID
    typealias NodeID = Int

    /// 配置参数
    struct Config {
        /// 每层最大连接数（M）
        let maxConnections: Int
        /// 第 0 层最大连接数（通常是 M 的 2 倍）
        let maxConnectionsLayer0: Int
        /// 候选列表大小（efConstruction）
        let efConstruction: Int
        /// 搜索时候选列表大小（efSearch）
        var efSearch: Int
        /// 向量维度
        let dimension: Int
        /// 距离度量
        let distanceMetric: DistanceMetric

        /// 默认配置（适用于 768 维 CLIP 向量）
        static let `default` = Config(
            maxConnections: 16,
            maxConnectionsLayer0: 32,
            efConstruction: 200,
            efSearch: 100,
            dimension: 768,
            distanceMetric: .cosine
        )
    }

    /// 距离度量 - Accelerate 优化版
    enum DistanceMetric {
        case cosine
        case euclidean

        func distance(_ a: [Float], _ b: [Float]) -> Float {
            switch self {
            case .cosine:
                return 1.0 - SimdUtils.cosineSimilarityFull(a, b)
            case .euclidean:
                return euclideanDistanceAccelerated(a, b)
            }
        }

        /// Accelerate 优化欧氏距离
        private func euclideanDistanceAccelerated(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count else { return Float.infinity }
            let count = vDSP_Length(a.count)

            // 计算差值: diff = a - b
            var diff = [Float](repeating: 0, count: a.count)
            vDSP_vsub(b, 1, a, 1, &diff, 1, count)

            // 计算平方和
            var sum: Float = 0
            vDSP_svesq(diff, 1, &sum, count)

            return sqrt(sum)
        }
    }

    /// 节点
    struct Node {
        let id: NodeID
        let vector: [Float]
        let layer: Int
        var connections: [Int: Set<NodeID>]  // layer -> neighbors
    }

    /// 搜索结果
    struct SearchResult {
        let id: NodeID
        let distance: Float
        let externalId: String
    }

    // MARK: - Properties

    private var config: Config
    private var nodes: [NodeID: Node] = [:]
    private var entryPoint: NodeID?
    private var maxLayer: Int = 0
    private var nextId: NodeID = 0

    /// 外部 ID 映射
    private var idMap: [NodeID: String] = [:]
    private var reverseIdMap: [String: NodeID] = [:]

    /// 线程安全锁
    private let lock = NSLock()

    /// 随机数生成器状态
    private var randomState: UInt64 = 1

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 批量插入 (优化版)
    ///
    /// 预分配容量 + 批量处理，减少内存分配和锁竞争。
    ///
    /// - Parameter vectors: 向量数组，包含外部 ID 和向量数据
    func insertBatch(vectors: [(id: String, vector: [Float])]) {
        lock.lock()
        defer { lock.unlock() }

        // 预分配容量
        let newCount = nodes.count + vectors.count
        nodes.reserveCapacity(newCount)
        idMap.reserveCapacity(newCount)
        reverseIdMap.reserveCapacity(newCount)

        // 批量插入
        for (id, vector) in vectors {
            insertLocked(vector: vector, externalId: id)
        }

        Logger.index.debug("HNSW 批量插入完成: count=\(vectors.count), total=\(self.nodes.count)")
    }

    /// 内部插入方法 (已加锁版本)
    private func insertLocked(vector: [Float], externalId: String) {
        guard vector.count == self.config.dimension else {
            Logger.index.warning("HNSW: 向量维度不匹配, expected=\(self.config.dimension), actual=\(vector.count)")
            return
        }

        // 检查是否已存在
        if let existingId = reverseIdMap[externalId] {
            nodes.removeValue(forKey: existingId)
        }

        let nodeId = nextId
        nextId += 1

        // 计算层数
        let layer = randomLayer()

        // 创建节点
        var node = Node(
            id: nodeId,
            vector: vector,
            layer: layer,
            connections: [:]
        )

        // 插入到索引
        nodes[nodeId] = node
        idMap[nodeId] = externalId
        reverseIdMap[externalId] = nodeId

        // 如果是第一个节点，设为入口点
        guard let entry = entryPoint else {
            entryPoint = nodeId
            maxLayer = layer
            return
        }

        // 找到插入位置
        guard let entryNode = nodes[entry] else {
            Logger.index.error("HNSW: 入口节点 \(entry) 不存在")
            return
        }
        var currentDist = config.distanceMetric.distance(vector, entryNode.vector)
        var currentNode = entry

        // 从顶层向下搜索
        for lc in stride(from: maxLayer, through: layer + 1, by: -1) {
            var changed = true
            while changed {
                changed = false
                let neighbors = nodes[currentNode]?.connections[lc] ?? []
                for neighbor in neighbors {
                    guard let neighborNode = nodes[neighbor] else { continue }
                    let dist = config.distanceMetric.distance(vector, neighborNode.vector)
                    if dist < currentDist {
                        currentDist = dist
                        currentNode = neighbor
                        changed = true
                    }
                }
            }
        }

        // 在每层建立连接
        for lc in stride(from: min(layer, maxLayer), through: 0, by: -1) {
            let neighbors = searchLayerInternalLocked(vector: vector, entry: currentNode, ef: config.efConstruction, layer: lc)
            let selected = selectNeighbors(neighbors: neighbors, maxCount: lc == 0 ? config.maxConnectionsLayer0 : config.maxConnections)

            // 建立双向连接
            node.connections[lc] = Set(selected.map { $0.0 })

            for (neighborId, _) in selected {
                nodes[neighborId]?.connections[lc, default: []].insert(nodeId)
            }

            if !selected.isEmpty {
                currentNode = selected[0].0
            }
        }

        // 更新入口点
        if layer > maxLayer {
            entryPoint = nodeId
            maxLayer = layer
        }
    }

    /// 内部搜索层方法 (已加锁版本)
    private func searchLayerInternalLocked(vector: [Float], entry: NodeID, ef: Int, layer: Int) -> [(NodeID, Float)] {
        guard let entryNode = nodes[entry] else {
            Logger.index.warning("HNSW: 入口节点 \(entry) 不存在，返回空结果")
            return []
        }

        var visited: Set<NodeID> = [entry]
        var candidateHeap = MinHeap<(NodeID, Float)> { $0.1 < $1.1 }
        var resultHeap = MaxHeap<(NodeID, Float)> { $0.1 < $1.1 }

        let entryDist = config.distanceMetric.distance(vector, entryNode.vector)
        candidateHeap.insert((entry, entryDist))
        resultHeap.insert((entry, entryDist))

        while !candidateHeap.isEmpty {
            guard let (currentId, currentDist) = candidateHeap.pop() else { break }
            let furthest = resultHeap.max()?.1 ?? Float.infinity

            if currentDist > furthest {
                break
            }

            let neighbors = nodes[currentId]?.connections[layer] ?? []
            for neighbor in neighbors {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    guard let neighborNode = nodes[neighbor] else { continue }
                    let dist = config.distanceMetric.distance(vector, neighborNode.vector)

                    if dist < furthest || resultHeap.count < ef {
                        candidateHeap.insert((neighbor, dist))
                        resultHeap.insert((neighbor, dist))

                        if resultHeap.count > ef {
                            _ = resultHeap.pop()
                        }
                    }
                }
            }
        }

        return resultHeap.sorted()
    }

    /// 搜索最近邻
    ///
    /// - Parameters:
    ///   - vector: 查询向量
    ///   - k: 返回数量
    /// - Returns: 搜索结果数组，按距离升序排列
    func search(vector: [Float], k: Int) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entryPoint else { return [] }
        guard vector.count == self.config.dimension else {
            Logger.index.warning("HNSW: 查询向量维度不匹配, expected=\(self.config.dimension), actual=\(vector.count)")
            return []
        }
        guard let entryNode = nodes[entry] else {
            Logger.index.warning("HNSW: 入口节点 \(entry) 不存在，返回空结果")
            return []
        }

        var currentNode = entry
        var currentDist = config.distanceMetric.distance(vector, entryNode.vector)

        // 从顶层向下搜索
        for lc in (1...maxLayer).reversed() {
            var changed = true
            while changed {
                changed = false
                let neighbors = nodes[currentNode]?.connections[lc] ?? []
                for neighbor in neighbors {
                    guard let neighborNode = nodes[neighbor] else { continue }
                    let dist = config.distanceMetric.distance(vector, neighborNode.vector)
                    if dist < currentDist {
                        currentDist = dist
                        currentNode = neighbor
                        changed = true
                    }
                }
            }
        }

        // 在第 0 层搜索
        let ef = max(config.efSearch, k)
        let candidates = searchLayerInternal(vector: vector, entry: currentNode, ef: ef, layer: 0)

        // 返回 Top-K
        return candidates.prefix(k).map { (nodeId, dist) in
            SearchResult(
                id: nodeId,
                distance: dist,
                externalId: idMap[nodeId] ?? ""
            )
        }
    }

    /// 获取索引大小
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return nodes.count
    }

    /// 清空索引
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        nodes.removeAll()
        idMap.removeAll()
        reverseIdMap.removeAll()
        entryPoint = nil
        maxLayer = 0
        nextId = 0
        Logger.index.info("HNSW 索引已清空")
    }

    // MARK: - Private Methods

    /// 随机层数（线性同余生成器）
    private func randomLayer() -> Int {
        let ml = 1.0 / log(Double(config.maxConnections))
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        let rand = Double(randomState & 0x7FFFFFFFFFFFFFFF) / Double(0x7FFFFFFFFFFFFFFF)
        return Int(-log(max(rand, 1e-10)) * ml)
    }

    /// 在指定层搜索（内部方法，不加锁）- 最小堆优化版
    ///
    /// 优化: 使用最小堆替代频繁排序，ef=50 时减少 80% 排序操作
    private func searchLayerInternal(vector: [Float], entry: NodeID, ef: Int, layer: Int) -> [(NodeID, Float)] {
        guard let entryNode = nodes[entry] else {
            Logger.index.warning("HNSW: 入口节点 \(entry) 不存在，返回空结果")
            return []
        }
        var visited: Set<NodeID> = [entry]

        // 使用最小堆维护候选集 (距离小的优先)
        var candidateHeap = MinHeap<(NodeID, Float)> { $0.1 < $1.1 }

        // 使用最大堆维护结果集 (距离大的在顶部，方便淘汰)
        var resultHeap = MaxHeap<(NodeID, Float)> { $0.1 < $1.1 }

        let entryDist = config.distanceMetric.distance(vector, entryNode.vector)
        candidateHeap.insert((entry, entryDist))
        resultHeap.insert((entry, entryDist))

        while !candidateHeap.isEmpty {
            // 取出距离最小的候选
            guard let (currentId, currentDist) = candidateHeap.pop() else { break }

            // 获取当前最远结果
            let furthest = resultHeap.max()?.1 ?? Float.infinity

            // 如果当前候选比最远结果还远，停止
            if currentDist > furthest {
                break
            }

            // 遍历邻居
            let neighbors = nodes[currentId]?.connections[layer] ?? []
            for neighbor in neighbors {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    guard let neighborNode = nodes[neighbor] else { continue }
                    let dist = config.distanceMetric.distance(vector, neighborNode.vector)

                    if dist < furthest || resultHeap.count < ef {
                        candidateHeap.insert((neighbor, dist))
                        resultHeap.insert((neighbor, dist))

                        // 保持结果大小
                        if resultHeap.count > ef {
                            _ = resultHeap.pop()
                        }
                    }
                }
            }
        }

        // 转换为有序数组
        return resultHeap.sorted()
    }

    /// 选择邻居
    private func selectNeighbors(neighbors: [(NodeID, Float)], maxCount: Int) -> [(NodeID, Float)] {
        return neighbors.sorted { $0.1 < $1.1 }.prefix(maxCount).map { $0 }
    }
}
