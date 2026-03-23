//
// SimilarityClusteringView.swift
// PhotoScanner
//
// 相似聚类功能页面（使用 DBSCAN 算法）
//

import SwiftUI
import Photos

struct SimilarityClusteringView: View {
    @Environment(\.services) private var services
    
    @State private var viewModel: SimilarityClusteringViewModel
    
    init(services: AppServices) {
        _viewModel = State(initialValue: SimilarityClusteringViewModel(services: services))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 阈值预设选择
                presetSection
                
                // 开始聚类按钮
                clusterButton
                
                // 结果显示
                resultSection
            }
            .padding()
        }
        .navigationTitle("相似聚类")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 阈值预设选择
    
    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("聚类模式")
                .font(.headline)
            
            // 五档选择器
            HStack(spacing: 8) {
                ForEach(ClusteringPreset.allCases) { preset in
                    Button(action: {
                        viewModel.selectedPreset = preset
                    }) {
                        VStack(spacing: 6) {
                            Text(preset.rawValue)
                                .font(.caption)
                                .fontWeight(viewModel.selectedPreset == preset ? .semibold : .regular)
                                .foregroundStyle(viewModel.selectedPreset == preset ? .white : .primary)
                            
                            Text(String(format: "%.0f%%", preset.threshold * 100))
                                .font(.caption2)
                                .foregroundStyle(viewModel.selectedPreset == preset ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            viewModel.selectedPreset == preset
                                ? Color.blue
                                : Color(.systemGray6)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 描述文字
            Text(viewModel.selectedPreset.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - 聚类按钮
    
    @ViewBuilder
    private var clusterButton: some View {
        Button(action: {
            Task {
                await viewModel.performClustering()
            }
        }) {
            HStack {
                if case .loading(let progress) = viewModel.state {
                    ProgressView()
                        .tint(.white)
                    Text(progress)
                        .font(.subheadline)
                } else {
                    Image(systemName: "square.grid.3x3.fill")
                    Text("开始聚类")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled({
            if case .loading = viewModel.state { return true }
            return false
        }())
    }
    
    // MARK: - 结果显示
    
    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.state {
        case .idle:
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("选择聚类模式后点击「开始聚类」")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            
        case .loading:
            EmptyView() // 按钮上显示进度
            
        case .loaded(let clusters):
            if clusters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("未找到相似图片组")
                        .font(.headline)
                    
                    Text("尝试选择「更宽容」模式")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("发现 \(clusters.count) 个相似组")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("重置") {
                            viewModel.reset()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    }
                    
                    ForEach(clusters) { cluster in
                        ClusterCard(
                            cluster: cluster,
                            thumbnail: viewModel.thumbnail(for: cluster.centerAssetId ?? "")
                        )
                    }
                }
            }
            
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                
                Text("聚类失败")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("重试") {
                    viewModel.reset()
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
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
    let services = AppServices(
        embeddingService: embedding,
        similarityEngine: similarity,
        indexStore: indexStore,
        vectorStore: vectorStore,
        indexEngine: indexEngine,
        searchEngine: searchEngine,
        photoLibraryAssetProvider: photoLibraryAssetProvider,
        runtimePerformanceStore: runtimePerformanceStore,
        thumbnailCache: thumbnailCache
    )
    
    NavigationStack {
        SimilarityClusteringView(services: services)
    }
}
