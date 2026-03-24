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
            PhotoScannerRootView(services: services)
                .environment(\.services, services)
        }
    }
}

// MARK: - 根视图（处理权限申请）

private struct PhotoScannerRootView: View {
    let services: AppServices
    @State private var accessState: PhotoLibraryAccessState = .notDetermined
    
    var body: some View {
        Group {
            switch accessState {
            case .fullAccess, .limitedAccess:
                // 有权限，显示主界面
                ContentView()
                    #if DEBUG
                    .overlay {
                        PerformanceOverlay()
                    }
                    #endif
                
            case .notDetermined:
                // 未申请权限，显示权限引导
                PermissionRequestView(accessState: $accessState)
                
            case .unavailable:
                // 权限被拒绝
                PermissionDeniedView()
            }
        }
        .task {
            // 检查当前权限状态
            accessState = await services.photoLibraryAssetProvider.currentAccessState()
            
            // 如果未确定，自动申请
            if accessState == .notDetermined {
                accessState = await services.photoLibraryAssetProvider.requestReadAccessIfNeeded()
            }
        }
    }
}

// MARK: - 权限申请视图

private struct PermissionRequestView: View {
    @Binding var accessState: PhotoLibraryAccessState
    @Environment(\.services) private var services
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "photo.stack")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            
            // 标题
            VStack(spacing: 8) {
                Text("访问照片库")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("PhotoScanner 需要访问您的照片库来建立搜索索引。照片将在本地处理，不会上传到任何服务器。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // 按钮
            Button {
                Task {
                    accessState = await services.photoLibraryAssetProvider.requestReadAccessIfNeeded()
                }
            } label: {
                HStack {
                    Image(systemName: "photo")
                    Text("允许访问照片库")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            
            // 说明
            Text("您可以在系统设置中随时更改此权限")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.bottom, 32)
    }
}

// MARK: - 权限被拒绝视图

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            
            VStack(spacing: 8) {
                Text("无法访问照片库")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("请在系统设置中允许 PhotoScanner 访问您的照片库，以使用搜索功能。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("前往设置")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
        }
        .padding(.bottom, 32)
    }
}
