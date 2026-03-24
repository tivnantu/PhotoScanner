//
// SimilarityClusteringView.swift
// PhotoScanner
//
// 相似聚类功能页面（参考 V1 设计）
//

import SwiftUI
import Photos
import OSLog

struct SimilarityClusteringView: View {
    @Environment(\.services) private var services
    
    @Bindable private var viewModel: SimilarityClusteringViewModel

    init(services: AppServices) {
        viewModel = SimilarityClusteringViewModel(services: services)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.canCluster {
                    indexNotReadyView
                } else if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.clusters.isEmpty {
                    emptyView
                } else {
                    clusterListView
                }
            }
            .navigationTitle("相似图片聚类")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.performClustering()
                        }
                    } label: {
                        Label(
                            viewModel.clusters.isEmpty ? "开始分析" : "重新分析",
                            systemImage: viewModel.clusters.isEmpty ? "wand.and.stars" : "arrow.clockwise"
                        )
                    }
                    .disabled(viewModel.isLoading || !viewModel.canCluster)
                }
            }
        }
        .task {
            await viewModel.checkIndexStatus()
        }
    }
    
    // MARK: - Subviews (参考 V1 设计)
    
    /// 索引未就绪时的提示视图
    private var indexNotReadyView: some View {
        ContentUnavailableView {
            Label(viewModel.indexStateDescription.title, systemImage: "clock")
        } description: {
            Text(viewModel.indexStateDescription.message)
        } actions: {
            if viewModel.isIndexFailed {
                Button("重试") {
                    // 触发索引导航或提示
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在分析相似图片...")
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("聚类失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task {
                    await viewModel.performClustering()
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无聚类结果", systemImage: "photo.stack")
        } description: {
            Text("点击右上角按钮开始分析相似图片")
        } actions: {
            Button("开始分析") {
                Task {
                    await viewModel.performClustering()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var clusterListView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 聚类预设选择卡片（参考 V1 tuningCard）
                tuningCard
                    .padding(.horizontal, 20)
                
                // 统计卡片
                if let stats = viewModel.statistics {
                    statisticsCard(stats)
                        .padding(.horizontal, 20)
                }
                
                // 聚类结果网格（3列）
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(viewModel.clusters) { cluster in
                        NavigationLink(value: cluster) {
                            ClusterGridItem(
                                cluster: cluster,
                                thumbnail: viewModel.thumbnail(for: cluster.centerAssetId ?? "")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
        }
        .navigationDestination(for: PhotoCluster.self) { cluster in
            ClusterDetailView(cluster: cluster, viewModel: viewModel)
        }
    }
    
    /// 聚类预设选择卡片（参考 V1 设计）
    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("聚类模式", systemImage: "slider.horizontal.3")
                .font(.headline)
            
            Text("切换档位后，点击右上角重新分析即可生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                ForEach(ClusteringPreset.allCases) { preset in
                    Button {
                        viewModel.selectedPreset = preset
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                
                                Text(preset.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            if viewModel.selectedPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            viewModel.selectedPreset == preset
                                ? Color.accentColor.opacity(0.12)
                                : Color(.tertiarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(viewModel.selectedPreset.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    /// 统计卡片
    private func statisticsCard(_ stats: ClusteringStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("聚类统计", systemImage: "chart.bar")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatisticItem(title: "聚类数", value: "\(stats.clusterCount)")
                StatisticItem(title: "已分组", value: "\(stats.groupedPhotoCount)")
                StatisticItem(title: "平均每组", value: String(format: "%.1f", stats.averageClusterSize))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 统计项

private struct StatisticItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 聚类网格项（参考 V1 ClusterCard）

private struct ClusterGridItem: View {
    let cluster: PhotoCluster
    let thumbnail: UIImage?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // 缩略图
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    ZStack {
                        Color(.systemGray5)
                        
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 数量标签
                Text("\(cluster.assetIds.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(height: 120)
    }
}

// MARK: - 聚类详情视图（sheet）

private struct ClusterDetailView: View {
    let cluster: PhotoCluster
    let viewModel: SimilarityClusteringViewModel
    @Environment(\.dismiss) private var dismiss

    // 按需加载的缩略图缓存
    @State private var loadedThumbnails: [String: UIImage] = [:]

    // 网格列宽
    private let columnCount = 3
    private let spacing: CGFloat = 4

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount),
                    spacing: spacing
                ) {
                    ForEach(cluster.assetIds, id: \.self) { assetId in
                        thumbnailCell(for: assetId)
                    }
                }
                .padding(spacing)
            }
            .navigationTitle("\(cluster.assetIds.count) 张相似图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(for assetId: String) -> some View {
        let thumbnail = viewModel.thumbnail(for: assetId) ?? loadedThumbnails[assetId]

        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: assetId) {
            // 按需加载缺失的缩略图
            if thumbnail == nil {
                if let image = await viewModel.loadThumbnail(for: assetId) {
                    loadedThumbnails[assetId] = image
                }
            }
        }
    }
}

// MARK: - 聚类统计

struct ClusteringStatistics {
    let clusterCount: Int
    let groupedPhotoCount: Int
    let averageClusterSize: Double
}

// MARK: - Cluster Card

struct ClusterCard: View {
    let cluster: PhotoCluster
    let thumbnail: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                ZStack {
                    Color(.systemGray5)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                    
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(cluster.assetIds.count) 张相似图片")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(String(format: "%.0f%%", cluster.similarityScore * 100))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
                
                Text("聚类中心代表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
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
    let runtimePerformanceStore = RuntimePerformanceStore()
    let thumbnailCache = ThumbnailCache()
    let photoLibraryAssetProvider = PhotoLibraryAssetProvider(
        performanceStore: runtimePerformanceStore,
        thumbnailCache: thumbnailCache
    )
    let indexEngine = IndexEngine(
        embeddingService: embedding,
        indexStore: indexStore,
        vectorStore: vectorStore,
        photoLibraryAssetProvider: photoLibraryAssetProvider,
        performanceStore: runtimePerformanceStore
    )
    let searchEngine = SearchEngine(
        embeddingService: embedding,
        vectorStore: vectorStore,
        performanceStore: runtimePerformanceStore
    )
    let searchHistoryManager = SearchHistoryManager()
    let services = AppServices(
        embeddingService: embedding,
        similarityEngine: similarity,
        indexStore: indexStore,
        vectorStore: vectorStore,
        indexEngine: indexEngine,
        searchEngine: searchEngine,
        photoLibraryAssetProvider: photoLibraryAssetProvider,
        runtimePerformanceStore: runtimePerformanceStore,
        thumbnailCache: thumbnailCache,
        searchHistoryManager: searchHistoryManager
    )
    
    NavigationStack {
        SimilarityClusteringView(services: services)
    }
}
