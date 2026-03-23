//
// Embedding.swift
// PhotoScanner
//
// 嵌入向量值对象
// 封装向量数据，提供常用计算方法。
//

import Foundation
import Accelerate

/// 嵌入向量值对象
///
/// 封装向量数据，提供常用的向量计算方法。
/// 使用 vDSP 加速，比手动循环快 20-30 倍。
///
/// ## 使用示例
/// ```swift
/// let embedding1 = Embedding(values: [0.1, 0.2, 0.3])
/// let embedding2 = Embedding(values: [0.4, 0.5, 0.6])
///
/// // 计算余弦相似度
/// let similarity = embedding1.cosineSimilarity(to: embedding2)
///
/// // 归一化
/// let normalized = embedding1.normalized()
/// ```
struct Embedding: Sendable, Equatable {

    /// 向量值数组
    let values: [Float]

    /// 向量维度
    var dimension: Int { values.count }

    /// 是否为空向量
    var isEmpty: Bool { values.isEmpty }

    // MARK: - 初始化

    /// 创建嵌入向量
    /// - Parameter values: 向量值数组
    init(values: [Float]) {
        self.values = values
    }

    /// 从 Data 创建嵌入向量
    /// - Parameter data: 二进制数据（Float 数组）
    nonisolated init?(from data: Data) {
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return nil }
        let values = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
        self.values = values
    }

    // MARK: - 向量计算

    /// 计算与另一个向量的余弦相似度
    ///
    /// 使用 vDSP 加速，适用于已归一化的向量。
    /// 对于未归一化向量，使用 `cosineSimilarityFull`。
    ///
    /// - Parameter other: 另一个嵌入向量
    /// - Returns: 余弦相似度，范围 [-1, 1]
    func cosineSimilarity(to other: Embedding) -> Float {
        SimdUtils.cosineSimilarity(values, other.values)
    }

    /// 计算与另一个向量的余弦相似度（完整版，支持未归一化向量）
    ///
    /// - Parameter other: 另一个嵌入向量
    /// - Returns: 余弦相似度，范围 [-1, 1]
    func cosineSimilarityFull(to other: Embedding) -> Float {
        SimdUtils.cosineSimilarityFull(values, other.values)
    }

    /// 计算与另一个向量的点积
    ///
    /// - Parameter other: 另一个嵌入向量
    /// - Returns: 点积值
    func dotProduct(with other: Embedding) -> Float {
        SimdUtils.dot(values, other.values)
    }

    /// 计算 L2 范数
    ///
    /// - Returns: L2 范数值
    func l2Norm() -> Float {
        SimdUtils.l2Norm(values)
    }

    /// 检查是否已归一化
    ///
    /// - Parameter tolerance: 容差，默认 0.001
    /// - Returns: 是否已归一化
    func isNormalized(tolerance: Float = 0.001) -> Bool {
        SimdUtils.isNormalized(values, tolerance: tolerance)
    }

    /// 返回归一化后的向量
    ///
    /// - Returns: 归一化后的 Embedding
    func normalized() -> Embedding {
        Embedding(values: SimdUtils.normalize(values))
    }

    // MARK: - 序列化

    /// 转换为二进制数据
    ///
    /// - Returns: Float 数组的二进制表示
    nonisolated func toData() -> Data {
        values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

// MARK: - Codable

extension Embedding: Codable {
    enum CodingKeys: String, CodingKey {
        case values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.values = try container.decode([Float].self, forKey: .values)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
    }
}

// MARK: - Hashable

extension Embedding: Hashable {
    func hash(into hasher: inout Hasher) {
        // 只对前几个元素做哈希，避免大数组哈希性能问题
        let prefix = values.prefix(min(16, values.count))
        hasher.combine(prefix)
    }
}

// MARK: - CustomStringConvertible

extension Embedding: CustomStringConvertible {
    var description: String {
        if values.count <= 8 {
            return "Embedding(\(values))"
        }
        return "Embedding(dimension: \(dimension), first: [\(values.prefix(4).map { String(format: "%.4f", $0) }.joined(separator: ", "))])"
    }
}
