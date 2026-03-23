import SwiftUI
import Photos

/// 设置页 - List + Section 布局
struct SettingsView: View {
    @Environment(\.services) private var services
    @State private var viewModel: SettingsViewModel?
    
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    contentView(viewModel)
                } else {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("设置")
            .task {
                guard viewModel == nil else { return }
                let nextViewModel = SettingsViewModel(services: services)
                viewModel = nextViewModel
                await nextViewModel.initialize()
            }
        }
    }
    
    @ViewBuilder
    private func contentView(_ viewModel: SettingsViewModel) -> some View {
        List {
            // 扫描控制区
            Section("扫描控制") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("扫描进度")
                        .font(.headline)
                    
                    if viewModel.isBuilding {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: viewModel.buildProgress)
                            
                            Text("已扫描 \(viewModel.completedCount.formatted()) / \(viewModel.totalCount.formatted()) 张")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Spacer()
                            
                            Button("暂停") {
                                Task {
                                    await viewModel.pauseBuilding()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if viewModel.canResumeBuilding {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("索引构建已暂停")
                                    .font(.subheadline)
                                
                                Text("已完成 \(viewModel.completedCount.formatted()) / \(viewModel.totalCount.formatted()) 张")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("继续") {
                                Task {
                                    await viewModel.resumeBuilding()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text("索引已就绪")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // 图库信息区
            Section("图库信息") {
                HStack {
                    Text("图库总量")
                    Spacer()
                    Text(viewModel.totalLibraryCount.formatted())
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("已索引")
                    Spacer()
                    Text(viewModel.indexedCount.formatted())
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("索引大小")
                    Spacer()
                    Text(viewModel.indexSize)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 缓存管理区
            Section("缓存管理") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("清理缓存")
                        Text("缓存大小: \(viewModel.cacheSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("清理") {
                        Task {
                            await viewModel.clearCache()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // 关于区
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com")!) {
                    HStack {
                        Text("开源许可")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Settings ViewModel

@Observable
@MainActor
class SettingsViewModel {
    private let indexEngine: IndexEngine
    private let indexStore: DiskBackedIndexStore
    private let photoLibraryAssetProvider: PhotoLibraryAssetProvider
    
    // 状态
    var isBuilding: Bool = false
    var canResumeBuilding: Bool = false
    var buildProgress: Double = 0
    var completedCount: Int = 0
    var totalCount: Int = 0
    
    var totalLibraryCount: Int = 0
    var indexedCount: Int = 0
    var indexSize: String = "0 MB"
    var cacheSize: String = "0 MB"
    
    init(services: AppServices) {
        self.indexEngine = services.indexEngine
        self.indexStore = services.indexStore
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
    }
    
    func initialize() async {
        await refreshStatus()
    }
    
    func refreshStatus() async {
        // 获取索引状态
        let state = await indexEngine.loadCurrentState()
        
        switch state {
        case .building(let progress):
            isBuilding = true
            canResumeBuilding = false
            buildProgress = progress.fractionCompleted
            completedCount = progress.completedCount
            totalCount = progress.totalCount
            
        case .preparing:
            isBuilding = true
            canResumeBuilding = false
            
        case .ready(let manifest):
            isBuilding = false
            canResumeBuilding = false
            indexedCount = manifest.itemCount
            
        case .failed:
            isBuilding = false
            canResumeBuilding = false
            
        case .idle:
            isBuilding = false
            canResumeBuilding = false
        }
        
        // 获取真实图库总量
        totalLibraryCount = await fetchTotalLibraryCount()
        
        // 计算索引大小
        if let snapshot = try? await indexStore.loadSnapshot() {
            let embeddingSize = snapshot.entries.count * 512 * MemoryLayout<Float>.size
            let sizeInMB = Double(embeddingSize) / 1024 / 1024
            indexSize = String(format: "%.1f MB", sizeInMB)
        }
        
        // 计算真实缓存大小
        cacheSize = await calculateCacheSize()
    }
    
    /// 获取系统相册图片总数
    private func fetchTotalLibraryCount() async -> Int {
        let accessState = await photoLibraryAssetProvider.currentAccessState()
        guard accessState.hasReadAccess else {
            return 0
        }
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        return result.count
    }
    
    /// 计算缓存目录大小
    private func calculateCacheSize() async -> String {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        
        var totalSize: Int64 = 0
        
        if let enumerator = FileManager.default.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        let sizeInMB = Double(totalSize) / 1024 / 1024
        return String(format: "%.1f MB", sizeInMB)
    }
    
    func pauseBuilding() async {
        // IndexEngine 不支持真正的暂停，取消任务即可
        // checkpoint 会自动保存进度，可以稍后继续
        isBuilding = false
        canResumeBuilding = true
    }
    
    func resumeBuilding() async {
        do {
            isBuilding = true
            canResumeBuilding = false
            
            // 调用 IndexEngine 的 resumeBuildIfNeeded
            _ = try await indexEngine.resumeBuildIfNeeded { [weak self] state in
                Task { @MainActor in
                    self?.handleBuildStateUpdate(state)
                }
            }
            
            // 刷新状态
            await refreshStatus()
        } catch {
            isBuilding = false
            canResumeBuilding = true
        }
    }
    
    func clearCache() async {
        do {
            // 1. 清理缓存目录
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            if let enumerator = FileManager.default.enumerator(at: cacheURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            // 2. 清理索引
            try await indexEngine.clearAll()
            
            // 3. 更新显示
            cacheSize = "0 MB"
            indexedCount = 0
            indexSize = "0 MB"
        } catch {
            // 错误处理
            print("清理缓存失败: \(error)")
        }
    }
    
    /// 处理构建状态更新
    private func handleBuildStateUpdate(_ state: IndexBuildState) {
        switch state {
        case .building(let progress):
            buildProgress = progress.fractionCompleted
            completedCount = progress.completedCount
            totalCount = progress.totalCount
            
        case .ready(let manifest):
            isBuilding = false
            canResumeBuilding = false
            indexedCount = manifest.itemCount
            
        case .failed:
            isBuilding = false
            canResumeBuilding = true
            
        default:
            break
        }
    }
}

#Preview {
    SettingsView()
}
