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

    /// 磁盘索引存储
    let indexStore: DiskBackedIndexStore

    /// 向量检索存储（当前为 mmap 精确检索）
    let vectorStore: any VectorStore

    /// 索引构建引擎
    let indexEngine: IndexEngine

    /// 文搜图搜索引擎
    let searchEngine: SearchEngine

    /// 真实系统相册资产读取服务
    let photoLibraryAssetProvider: PhotoLibraryAssetProvider
}
