//
// PhotoScannerApp.swift
// PhotoScanner
//
// Composition Root：在这里组装所有依赖，通过 Environment 向下注入。
// 业务代码不在这里，只做"接线"。
//

import SwiftUI
import OSLog

@main
struct PhotoScannerApp: App {

    // MARK: - 服务（let 而非 @State，避免 SwiftUI 重建时丢失）

    private let services: AppServices

    // MARK: - 初始化（Composition Root）

    init() {
        // 组装 Plugin → Engine → Services
        let plugin = ChineseCLIPPlugin()
        let embeddingService = EmbeddingService(plugin: plugin)
        let similarityEngine = SimilarityEngine(embeddingService: embeddingService)

        services = AppServices(
            embeddingService: embeddingService,
            similarityEngine: similarityEngine
        )

        Logger.app.info("PhotoScanner 启动")
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.services, services)
        }
    }
}
