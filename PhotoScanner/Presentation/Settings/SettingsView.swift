import SwiftUI
import Photos
import OSLog

/// 设置页 - 借鉴 V1 设计的卡片式布局
struct SettingsView: View {
    @Environment(\.services) private var services
    @State private var viewModel: SettingsViewModel?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let viewModel {
                        // 照片库状态卡片（V1 风格）
                        PhotoLibrarySection(viewModel: viewModel)
                        
                        // 存储空间
                        StorageSection(viewModel: viewModel)
                        
                        // 运行状态
                        SystemStatusSection(viewModel: viewModel)
                        
                        // 关于
                        AboutSection()
                    } else {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .task {
                guard viewModel == nil else { return }
                let nextViewModel = SettingsViewModel(services: services)
                viewModel = nextViewModel
                await nextViewModel.initialize()
            }
        }
    }
}

// MARK: - 照片库状态卡片

private struct PhotoLibrarySection: View {
    let viewModel: SettingsViewModel
    @State private var showRebuildConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text("照片库")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            // 状态卡片（V1 IndexStatusCard 风格）
            IndexStatusCard(viewModel: viewModel)
            
            // 操作按钮
            actionButtons
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 构建中/暂停中：显示暂停/继续按钮
            if viewModel.isBuilding {
                SettingsButton(
                    label: "暂停分析",
                    icon: "pause.fill",
                    iconColor: .orange
                ) {
                    Task { await viewModel.pauseBuilding() }
                }
            } else if viewModel.canResumeBuilding {
                SettingsButton(
                    label: "继续分析",
                    icon: "play.fill",
                    iconColor: .green
                ) {
                    Task { await viewModel.resumeBuilding() }
                }
            } else if viewModel.indexedCount == 0 {
                // 未开始
                SettingsButton(
                    label: "开始扫描",
                    icon: "arrow.trianglehead.clockwise",
                    iconColor: .blue
                ) {
                    Task { await viewModel.resumeBuilding() }
                }
            } else {
                // 已就绪但有待处理
                if viewModel.totalLibraryCount > viewModel.indexedCount {
                    SettingsButton(
                        label: "继续扫描",
                        icon: "arrow.trianglehead.clockwise",
                        iconColor: .blue
                    ) {
                        Task { await viewModel.resumeBuilding() }
                    }
                }
                
                // 重新分析
                SettingsButton(
                    label: "重新分析所有照片",
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .secondary,
                    isDestructive: false
                ) {
                    showRebuildConfirmation = true
                }
                .confirmationDialog(
                    "重新分析所有照片",
                    isPresented: $showRebuildConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("重新分析", role: .destructive) {
                        Task {
                            await viewModel.clearCache()
                            await viewModel.resumeBuilding()
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将清除已有的分析数据，重新扫描全部照片。过程中已有搜索功能不受影响。")
                }
            }
        }
    }
}

// MARK: - 索引状态卡片（V1 风格）

private struct IndexStatusCard: View {
    let viewModel: SettingsViewModel
    
    var body: some View {
        Group {
            if viewModel.isBuilding {
                buildingCard
            } else if viewModel.canResumeBuilding {
                pausedCard
            } else if viewModel.indexedCount > 0 {
                readyCard
            } else {
                idleCard
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // 未开始
    private var idleCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.gray)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("尚未建立搜索数据")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if viewModel.totalLibraryCount > 0 {
                    Text("相册共 \(viewModel.totalLibraryCount.formatted()) 张照片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // 构建中
    private var buildingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .symbolEffect(.rotate, isActive: true)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在分析照片")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if viewModel.totalCount > 0 {
                        Text("\(viewModel.completedCount.formatted()) / \(viewModel.totalCount.formatted()) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        Text("正在获取照片信息...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
            }
            
            if viewModel.totalCount > 0 {
                ProgressView(value: Double(viewModel.completedCount), total: Double(max(viewModel.totalCount, 1)))
                    .tint(.blue)
            }
        }
    }
    
    // 已暂停
    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("分析已暂停")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("\(viewModel.completedCount.formatted()) / \(viewModel.totalCount.formatted()) 张 · 已完成的部分可正常搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                
                Spacer()
            }
            
            if viewModel.totalCount > 0 {
                ProgressView(value: Double(viewModel.completedCount), total: Double(max(viewModel.totalCount, 1)))
                    .tint(.orange)
            }
        }
    }
    
    // 已就绪
    private var readyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("搜索数据已就绪")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("已索引 \(viewModel.indexedCount.formatted()) 张照片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            
            Spacer()
        }
    }
}

// MARK: - 设置按钮组件

private struct SettingsButton: View {
    let label: String
    let icon: String
    let iconColor: Color
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isDestructive ? .red : iconColor)
                    .frame(width: 28, height: 28)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isDestructive ? .red : .primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 存储空间

private struct StorageSection: View {
    let viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("存储空间")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                InfoRow(label: "图库总量", value: viewModel.totalLibraryCount.formatted())
                
                Divider()
                    .padding(.leading, 16)
                
                InfoRow(label: "已索引", value: viewModel.indexedCount.formatted())
                
                Divider()
                    .padding(.leading, 16)
                
                InfoRow(label: "索引大小", value: viewModel.indexSize)
                
                Divider()
                    .padding(.leading, 16)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("缓存")
                            .font(.subheadline)
                        Text(viewModel.cacheSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("清理") {
                        Task { await viewModel.clearCache() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 信息行

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 运行状态

private struct SystemStatusSection: View {
    let viewModel: SettingsViewModel
    @State private var memoryUsage: String = "--"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("运行状态")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                InfoRow(label: "内存占用", value: memoryUsage)
                
                Divider()
                    .padding(.leading, 16)
                
                InfoRow(label: "索引状态", value: indexStateDescription)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .task {
            await updateMemoryUsage()
        }
    }
    
    private var indexStateDescription: String {
        if viewModel.isBuilding {
            return "分析中 \(viewModel.completedCount)/\(viewModel.totalCount)"
        } else if viewModel.canResumeBuilding {
            return "已暂停 \(viewModel.completedCount)/\(viewModel.totalCount)"
        } else if viewModel.indexedCount > 0 {
            return "已就绪 \(viewModel.indexedCount) 张"
        } else {
            return "未开始"
        }
    }
    
    private func updateMemoryUsage() async {
        // 简单估算：embedding 大小 + 一些开销
        let embeddingSize = viewModel.indexedCount * 512 * MemoryLayout<Float>.size
        let totalSize = embeddingSize + 50 * 1024 * 1024  // 50MB 开销
        let sizeInMB = Double(totalSize) / 1024 / 1024
        memoryUsage = sizeInMB > 0 ? String(format: "%.1f MB", sizeInMB) : "--"
    }
}

// MARK: - 关于

private struct AboutSection: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("关于")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                InfoRow(label: "版本", value: "v\(appVersion)")
                
                Divider()
                    .padding(.leading, 16)
                
                Link(destination: URL(string: "https://github.com")!) {
                    HStack {
                        Text("开源许可")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
