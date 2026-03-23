//
// SimilarityClusteringView.swift
// PhotoScanner
//
// 相似聚类功能页面
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
                // 参数设置区域
                parameterSection
                
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
    
    // MARK: - 参数设置区域
    
    @ViewBuilder
    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("聚类参数")
                .font(.headline)
            
            // 相似度阈值
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("相似度阈值")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(String(format: "%.2f", viewModel.similarityThreshold))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                }
                
                Slider(value: $viewModel.similarityThreshold, in: 0.5...1.0, step: 0.05)
                    .tint(.purple)
                
                Text("相似度 ≥ \(String(format: "%.2f", viewModel.similarityThreshold)) 的图片会被分为一组")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // 最小簇大小
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最小簇大小")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("\(viewModel.minClusterSize) 张")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                }
                
                Stepper("", value: $viewModel.minClusterSize, in: 2...10)
                    .labelsHidden()
                
                Text("少于 \(viewModel.minClusterSize) 张的组将被过滤")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                if case .loading = viewModel.state {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.grid.3x3.fill")
                }
                
                Text("开始聚类")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
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
                
                Text("调整参数后点击「开始聚类」")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在分析图片相似性...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
        case .loaded(let clusters):
            if clusters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("未找到相似图片组")
                        .font(.headline)
                    
                    Text("尝试降低相似度阈值")
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
                    }
                    
                    ForEach(clusters) { cluster in
                        ClusterCard(cluster: cluster)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(cluster.assetIds.count) 张相似图片")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(String(format: "相似度 %.0f%%", cluster.similarityScore * 100))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
            }
            
            Text("ID: \(cluster.assetIds.prefix(3).joined(separator: ", "))...")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    let photoLibraryAssetProvider = PhotoLibraryAssetProvider(performanceStore: runtimePerformanceStore)
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
        runtimePerformanceStore: runtimePerformanceStore
    )
    
    return NavigationStack {
        SimilarityClusteringView(services: services)
    }
}
