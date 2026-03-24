import SwiftUI
import Photos
import OSLog
import UIKit
import Darwin

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
    @Bindable var viewModel: SettingsViewModel
    @State private var showRebuildConfirmation = false
    @State private var showLimitPicker = false
    
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
            
            // 扫描数量选择器
            scanLimitRow
            
            // 操作按钮
            actionButtons
        }
    }
    
    @ViewBuilder
    private var scanLimitRow: some View {
        Button {
            showLimitPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                
                Text("扫描数量")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(viewModel.selectedLimit.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
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
        .disabled(viewModel.isBuilding)
        .sheet(isPresented: $showLimitPicker) {
            ScanLimitPickerSheet(
                selectedLimit: $viewModel.selectedLimit,
                isPresented: $showLimitPicker
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
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
                    viewModel.pauseBuilding()
                }
            } else if viewModel.canResumeBuilding {
                SettingsButton(
                    label: "继续分析",
                    icon: "play.fill",
                    iconColor: .green
                ) {
                    viewModel.resumeBuilding()
                }
            } else if viewModel.indexedCount == 0 {
                // 未开始
                SettingsButton(
                    label: "开始扫描",
                    icon: "arrow.trianglehead.clockwise",
                    iconColor: .blue
                ) {
                    viewModel.resumeBuilding()
                }
            } else {
                // 已就绪但有待处理
                if viewModel.totalLibraryCount > viewModel.indexedCount {
                    SettingsButton(
                        label: "继续扫描",
                        icon: "arrow.trianglehead.clockwise",
                        iconColor: .blue
                    ) {
                        viewModel.resumeBuilding()
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
                            viewModel.resumeBuilding()
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
                    Text("正在获取缩略图")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if viewModel.totalCount > 0 {
                        Text("已获取 \(viewModel.successCount.formatted()) 张 · 处理中 \(viewModel.completedCount.formatted()) / \(viewModel.totalCount.formatted()) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        Text("正在初始化...")
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
    @State private var timer: Timer?
    
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
        .onAppear {
            updateMemoryUsage()
            // 每秒刷新一次内存占用
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateMemoryUsage()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
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
    
    private func updateMemoryUsage() {
        // 使用 MemoryMonitor 获取真实的 App 内存占用
        let usageMB = MemoryMonitor.currentMemoryMB()
        memoryUsage = String(format: "%.1f MB", usageMB)
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

// MARK: - 张数限制选项

enum PhotoScanLimit: Int, CaseIterable, Identifiable {
    case limit1k = 1000
    case limit3k = 3000
    case limit5k = 5000
    case limit8k = 8000
    case limit10k = 10000
    case limit15k = 15000
    case limit20k = 20000
    case unlimited = 0
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .limit1k: return "1,000"
        case .limit3k: return "3,000"
        case .limit5k: return "5,000"
        case .limit8k: return "8,000"
        case .limit10k: return "10,000"
        case .limit15k: return "15,000"
        case .limit20k: return "20,000"
        case .unlimited: return "无限制"
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
    var successCount: Int = 0  // 成功获取缩略图数量
    
    var totalLibraryCount: Int = 0
    var indexedCount: Int = 0
    var indexSize: String = "0 MB"
    var cacheSize: String = "0 MB"
    
    // 张数限制（默认 3000）
    var selectedLimit: PhotoScanLimit = .limit3k
    
    // 构建任务（用于取消）
    private var buildTask: Task<Void, Never>?
    
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
    
    func pauseBuilding() {
        // 取消构建任务
        buildTask?.cancel()
        buildTask = nil
        
        // 更新状态
        isBuilding = false
        canResumeBuilding = true
        
        Logger.app.info("用户暂停索引构建")
    }
    
    func resumeBuilding() {
        // 如果已有任务在运行，先取消
        buildTask?.cancel()
        
        // 创建新的构建任务
        buildTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.isBuilding = true
                self.canResumeBuilding = false
            }
            
            do {
                // 先检查是否有 checkpoint 可以恢复
                let state = await self.indexEngine.loadCurrentState()
                
                switch state {
                case .building, .preparing:
                    // 已有进行中的构建，恢复它
                    _ = try await self.indexEngine.resumeBuildIfNeeded { [weak self] buildState in
                        Task { @MainActor in
                            self?.handleBuildStateUpdate(buildState)
                        }
                    }
                    
                case .idle, .ready:
                    // 没有进行中的构建，从相册导入并构建
                    try await self.startBuildingFromPhotoLibrary()
                    
                case .failed:
                    // 上次失败了，尝试恢复
                    _ = try await self.indexEngine.resumeBuildIfNeeded { [weak self] buildState in
                        Task { @MainActor in
                            self?.handleBuildStateUpdate(buildState)
                        }
                    }
                }
                
                // 构建完成（或取消），刷新状态
                await self.refreshStatus()
                
                await MainActor.run {
                    self.isBuilding = false
                    self.canResumeBuilding = false
                }
            } catch {
                Logger.app.error("索引构建失败: \(error)")
                await MainActor.run {
                    self.isBuilding = false
                    self.canResumeBuilding = true
                }
            }
        }
    }
    
    /// 从系统相册获取图片并开始构建索引
    private func startBuildingFromPhotoLibrary() async throws {
        // 先请求相册访问权限
        let accessState = await photoLibraryAssetProvider.requestReadAccessIfNeeded()
        guard accessState.hasReadAccess else {
            throw PSError.invalidInput("没有相册访问权限，请在系统设置中授权")
        }

        // 获取所有图片资源
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

        guard fetchResult.count > 0 else {
            throw PSError.invalidInput("相册中没有图片")
        }

        // 限制最大索引数量（根据用户选择）
        let limit = selectedLimit.rawValue
        let maxIndexCount = limit > 0 ? min(fetchResult.count, limit) : fetchResult.count

        Logger.app.info("开始从相册导入 \(maxIndexCount) 张图片用于索引（限制: \(self.selectedLimit.displayName)）")

        // 提前设置总数，让用户看到真实进度
        await MainActor.run {
            self.totalCount = maxIndexCount
        }

        // 限制并发度（参考 V1 串行模式，避免 PHImageManager 过载）
        let maxConcurrent = 4
        var inputs: [IndexedAssetInput] = []
        var failedCount = 0

        await withTaskGroup(of: (input: IndexedAssetInput?, index: Int).self) { group in
            var active = 0
            var nextIndex = 0

            while nextIndex < maxIndexCount || active > 0 {
                // 添加新任务直到达到并发限制
                while active < maxConcurrent && nextIndex < maxIndexCount {
                    let i = nextIndex
                    let asset = fetchResult.object(at: i)
                    let localIdentifier = asset.localIdentifier
                    let createdAt = asset.creationDate ?? Date()

                    group.addTask {
                        guard let thumbnailData = await self.photoLibraryAssetProvider.previewResource(for: localIdentifier)?.previewData else {
                            return (nil, i)
                        }
                        do {
                            let input = try IndexedAssetInput(
                                photoLibraryAssetIdentifier: localIdentifier,
                                imageData: thumbnailData,
                                createdAt: createdAt
                            )
                            return (input, i)
                        } catch {
                            return (nil, i)
                        }
                    }
                    active += 1
                    nextIndex += 1
                }

                // 等待一个任务完成
                if let result = await group.next() {
                    active -= 1
                    if let input = result.input {
                        inputs.append(input)
                    } else {
                        failedCount += 1
                    }

                    // 更新进度
                    let completed = nextIndex - active
                    await MainActor.run {
                        self.completedCount = completed
                        self.successCount = inputs.count
                    }

                    // 每 100 张打印一次进度
                    if completed % 100 == 0 {
                        Logger.app.info("已处理 \(completed)/\(maxIndexCount) 张，成功 \(inputs.count) 张，失败 \(failedCount) 张")
                    }
                }
            }
        }

        guard !inputs.isEmpty else {
            throw PSError.invalidInput("没有可索引的图片")
        }

        Logger.app.info("导入完成：成功 \(inputs.count) 张，失败 \(failedCount) 张，开始构建索引")
        
        // 调用 addAssetsAndRebuild 开始构建
        _ = try await indexEngine.addAssetsAndRebuild(inputs) { [weak self] buildState in
            Task { @MainActor in
                self?.handleBuildStateUpdate(buildState)
            }
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

// MARK: - 张数限制选择器 Sheet

private struct ScanLimitPickerSheet: View {
    @Binding var selectedLimit: PhotoScanLimit
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部操作栏
            HStack {
                Button("取消") {
                    isPresented = false
                }
                
                Spacer()
                
                Text("扫描数量")
                    .font(.headline)
                
                Spacer()
                
                Button("确定") {
                    isPresented = false
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // Wheel 选择器
            Picker("扫描数量", selection: $selectedLimit) {
                ForEach(PhotoScanLimit.allCases) { limit in
                    Text(limit.displayName)
                        .tag(limit)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 180)
            
            // 警告提示（选择无限制时显示）
            if selectedLimit == .unlimited {
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        
                        Text("扫描大量照片将占用较大磁盘空间并延长分析时间")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
