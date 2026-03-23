//
// AppServices.swift
// PhotoScanner
//
// 服务引用聚合。
// 只是各 Engine 服务的集合引用，不包含业务逻辑。
// 通过 EnvironmentKey 注入到 SwiftUI 视图树。
//

import Foundation

// MARK: - AppServices

struct AppServices {

    /// Embedding 服务（图像/文本 → 向量）
    let embeddingService: EmbeddingService

    /// 相似度引擎（图文相似度计算）
    let similarityEngine: SimilarityEngine

    /// 向量检索存储（最小 Top-K 检索）
    let vectorStore: any VectorStore
}
