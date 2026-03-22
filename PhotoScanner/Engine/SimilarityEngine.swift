//
// SimilarityEngine.swift
// PhotoScanner
//
// 相似度计算的业务门面。
// 接收原始输入（图像 + 文本），输出相似度分数。
// 这是第一阶段的核心交付能力。
//

import Foundation
import OSLog

// MARK: - SimilarityEngine

final class SimilarityEngine: Sendable {

    // MARK: - 依赖

    private let embeddingService: EmbeddingService

    // MARK: - 初始化

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }

    // MARK: - 相似度计算

    /// 计算图文相似度
    ///
    /// - Parameters:
    ///   - imageData: 原始图像数据
    ///   - text: 查询文本
    /// - Returns: 余弦相似度分数（-1.0 ~ 1.0，通常在 0 ~ 1.0 之间）
    func computeSimilarity(imageData: Data, text: String) async throws -> Float {
        Logger.search.debug("计算图文相似度，文本: \(text)")

        let imageEmbedding = try await embeddingService.embedImage(imageData)
        let textEmbedding = try await embeddingService.embedText(text)

        let score = dotProduct(imageEmbedding, textEmbedding)

        Logger.search.info("图文相似度: \(score, format: .fixed(precision: 4)), 文本: \(text)")
        return score
    }

    // MARK: - 内部工具

    /// 两个向量的点积（已归一化的向量点积即余弦相似度）
    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var result: Float = 0
        for i in 0..<a.count {
            result += a[i] * b[i]
        }
        return result
    }
}
