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
    /// - Returns: 余弦相似度分数（-1.0 ~ 1.0）
    func computeSimilarity(imageData: Data, text: String) async throws -> Float {
        guard !imageData.isEmpty else {
            throw PSError.invalidInput("图像数据不能为空")
        }

        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            throw PSError.invalidInput("文本不能为空")
        }

        Logger.search.debug("开始计算图文相似度，文本长度: \(sanitizedText.count)")

        let imageEmbedding = try await embeddingService.embedImage(imageData)
        let textEmbedding = try await embeddingService.embedText(sanitizedText)

        let rawScore = try dotProduct(imageEmbedding, textEmbedding)
        let clampedScore = max(-1, min(1, rawScore))

        Logger.search.info("图文相似度计算完成: \(clampedScore, format: .fixed(precision: 4))")
        return clampedScore
    }

    // MARK: - 内部工具

    /// 两个向量的点积（已归一化的向量点积即余弦相似度）
    private func dotProduct(_ a: [Float], _ b: [Float]) throws -> Float {
        guard !a.isEmpty, !b.isEmpty else {
            throw PSError.invalidModelOutput("相似度计算输入向量不能为空")
        }

        guard a.count == b.count else {
            throw PSError.invalidModelOutput(
                "相似度计算维度不匹配：image=\(a.count), text=\(b.count)"
            )
        }

        return SimdUtils.dot(a, b)
    }
}
