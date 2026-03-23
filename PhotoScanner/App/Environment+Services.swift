//
// Environment+Services.swift
// PhotoScanner
//
// 通过 SwiftUI Environment 机制注入 AppServices。
// 遵循 Composition Root 模式：只在 App 入口组装，下游只消费。
//

import SwiftUI

// MARK: - EnvironmentKey

private struct ServicesKey: EnvironmentKey {

    // 默认值使用空插件，确保 Preview 和测试能正常运行
    static let defaultValue: AppServices = {
        let plugin = EmptyModelPlugin()
        let embedding = EmbeddingService(plugin: plugin)
        let similarity = SimilarityEngine(embeddingService: embedding)
        let indexStore = DiskBackedIndexStore(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "PhotoScannerPreviewIndex",
                isDirectory: true
            )
        )
        let vectorStore = MMapBruteForceVectorStore(indexStore: indexStore)
        let indexEngine = IndexEngine(
            embeddingService: embedding,
            indexStore: indexStore,
            vectorStore: vectorStore
        )
        let searchEngine = SearchEngine(
            embeddingService: embedding,
            vectorStore: vectorStore
        )
        return AppServices(
            embeddingService: embedding,
            similarityEngine: similarity,
            indexStore: indexStore,
            vectorStore: vectorStore,
            indexEngine: indexEngine,
            searchEngine: searchEngine
        )
    }()
}

// MARK: - EnvironmentValues 扩展

extension EnvironmentValues {
    var services: AppServices {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}
