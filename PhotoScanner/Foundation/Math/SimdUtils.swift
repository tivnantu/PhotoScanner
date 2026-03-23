//
// SimdUtils.swift
// PhotoScanner
//
// 高性能向量运算工具
// 基于 Accelerate (vDSP) 和 SIMD 框架，提供向量点积、归一化、余弦相似度等运算。
// 对 512 维向量（Chinese-CLIP ViT-B/16），vDSP 比手动循环快约 20-30 倍。
//

import Accelerate
import simd

/// 高性能向量运算工具
///
/// 基于 Accelerate (vDSP) 和 SIMD 框架，提供向量点积、归一化、余弦相似度等运算。
/// 对 512 维向量（Chinese-CLIP ViT-B/16），vDSP 比手动循环快约 20-30 倍。
///
/// ## 性能优势
/// - 点积计算：vDSP_dotpr 比手动循环快 20-30 倍
/// - 归一化：vDSP_vsdiv 避免分支预测失败
/// - L2 范数：vDSP_svesq 单指令完成平方和
///
/// ## 使用示例
/// ```swift
/// let embedding1 = try await embeddingService.embed(image)
/// let embedding2 = try await embeddingService.embed(text)
///
/// // 已归一化向量直接用点积
/// let similarity = SimdUtils.cosineSimilarity(embedding1, embedding2)
///
/// // 未归一化向量用完整计算
/// let similarity = SimdUtils.cosineSimilarityFull(embedding1, embedding2)
/// ```
enum SimdUtils {

    // MARK: - 点积

    /// 计算两个向量的点积（vDSP 加速）
    ///
    /// 使用 vDSP_dotpr 进行向量化点积计算，比手动循环快 20-30 倍。
    ///
    /// - Parameters:
    ///   - a: 第一个向量
    ///   - b: 第二个向量
    /// - Returns: 点积结果
    /// - Precondition: 两个向量长度必须一致
    @inlinable
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "向量长度必须一致: a.count=\(a.count), b.count=\(b.count)")
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    // MARK: - 余弦相似度

    /// 已归一化向量的余弦相似度（等价于点积）
    ///
    /// 当向量已归一化时，余弦相似度等价于点积。
    /// 这是一个 O(n) 操作，使用 vDSP 加速。
    ///
    /// - Parameters:
    ///   - a: 已归一化的第一个向量
    ///   - b: 已归一化的第二个向量
    /// - Returns: 余弦相似度，范围 [-1, 1]
    /// - Note: 如果向量未归一化，结果可能超出 [-1, 1] 范围
    @inlinable
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        dot(a, b)
    }

    /// 通用余弦相似度（支持未归一化向量）
    ///
    /// 计算公式: cos(a, b) = (a · b) / (||a|| * ||b||)
    ///
    /// - Parameters:
    ///   - a: 第一个向量（可以是未归一化的）
    ///   - b: 第二个向量（可以是未归一化的）
    /// - Returns: 余弦相似度，范围 [-1, 1]
    /// - Note: 对已归一化向量，使用 `cosineSimilarity` 更高效
    @inlinable
    static func cosineSimilarityFull(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let count = vDSP_Length(a.count)

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        // 并行计算点积和两个范数
        vDSP_dotpr(a, 1, b, 1, &dot, count)
        vDSP_svesq(a, 1, &normA, count)
        vDSP_svesq(b, 1, &normB, count)

        // 防止除零
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    // MARK: - L2 范数

    /// 计算 L2 范数（欧几里得范数）
    ///
    /// L2 范数 = sqrt(sum(x_i^2))
    ///
    /// - Parameter vector: 输入向量
    /// - Returns: L2 范数值
    @inlinable
    static func l2Norm(_ vector: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(vector, 1, &sum, vDSP_Length(vector.count))
        return sqrt(sum)
    }

    // MARK: - 归一化

    /// 检查向量是否已归一化（L2 norm ≈ 1）
    ///
    /// - Parameters:
    ///   - vector: 待检查向量
    ///   - tolerance: 容差，默认 0.001（收紧以提高精度）
    /// - Returns: 是否已归一化
    @inlinable
    static func isNormalized(_ vector: [Float], tolerance: Float = 0.001) -> Bool {
        let norm = l2Norm(vector)
        return abs(norm - 1.0) < tolerance
    }

    /// L2 归一化（返回新向量）
    ///
    /// 将向量归一化为单位向量（L2 norm = 1）。
    /// 如果向量已归一化，直接返回原向量避免精度损失。
    ///
    /// - Parameter vector: 待归一化向量
    /// - Returns: 归一化后的向量
    /// - Note: 零向量返回原向量
    @inlinable
    static func normalize(_ vector: [Float]) -> [Float] {
        // 检查是否已归一化，避免双重归一化导致的精度损失
        if isNormalized(vector) {
            return vector
        }
        let norm = l2Norm(vector)
        guard norm > 0 else { return vector }
        var result = [Float](repeating: 0, count: vector.count)
        var normValue = norm
        vDSP_vsdiv(vector, 1, &normValue, &result, 1, vDSP_Length(vector.count))
        return result
    }
}
