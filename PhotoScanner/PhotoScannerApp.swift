//
// PhotoScannerApp.swift
// PhotoScanner
//
// Composition Root：在这里组装所有依赖，通过 Environment 向下注入。
// 业务代码不在这里，只做"接线"。
//

import SwiftUI
import UIKit
import OSLog

@main
struct PhotoScannerApp: App {

    // MARK: - 服务（let 而非 @State，避免 SwiftUI 重建时丢失）

    private let services: AppServices

    // MARK: - 初始化（Composition Root）

    init() {
        // DEBUG 环境初始化崩溃处理器
        #if DEBUG
        CrashHandler.setup()
        #endif
        
        let plugin = ChineseCLIPPlugin()
        let embeddingService = EmbeddingService(plugin: plugin)
        let similarityEngine = SimilarityEngine(embeddingService: embeddingService)
        let indexStore = DiskBackedIndexStore()
        let vectorStore = MMapBruteForceVectorStore(indexStore: indexStore)
        let runtimePerformanceStore = RuntimePerformanceStore()
        
        // 缩略图缓存
        let thumbnailCache = ThumbnailCache()
        
        // 搜索历史管理器
        let searchHistoryManager = SearchHistoryManager()
        
        // 注入缓存到 PhotoLibraryAssetProvider
        let photoLibraryAssetProvider = PhotoLibraryAssetProvider(
            performanceStore: runtimePerformanceStore,
            thumbnailCache: thumbnailCache
        )
        
        let indexEngine = IndexEngine(
            embeddingService: embeddingService,
            indexStore: indexStore,
            vectorStore: vectorStore,
            photoLibraryAssetProvider: photoLibraryAssetProvider,
            performanceStore: runtimePerformanceStore
        )
        let searchEngine = SearchEngine(
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            performanceStore: runtimePerformanceStore
        )

        services = AppServices(
            embeddingService: embeddingService,
            similarityEngine: similarityEngine,
            indexStore: indexStore,
            vectorStore: vectorStore,
            indexEngine: indexEngine,
            searchEngine: searchEngine,
            photoLibraryAssetProvider: photoLibraryAssetProvider,
            runtimePerformanceStore: runtimePerformanceStore,
            thumbnailCache: thumbnailCache,
            searchHistoryManager: searchHistoryManager
        )

        Logger.app.info("PhotoScanner 启动")
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.services, services)
                #if DEBUG
                .overlay {
                    PerformanceOverlay()
                }
                #endif
        }
    }
}
