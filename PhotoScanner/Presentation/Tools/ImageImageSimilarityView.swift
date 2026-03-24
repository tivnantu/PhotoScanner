//
// ImageImageSimilarityView.swift
// PhotoScanner
//
// 图图相似度计算页面
//

import SwiftUI
import PhotosUI

struct ImageImageSimilarityView: View {
    @Environment(\.services) private var services
    
    @State private var viewModel: ImageImageSimilarityViewModel
    @State private var showPHPicker1 = false
    @State private var showPHPicker2 = false
    
    init(services: AppServices) {
        _viewModel = State(initialValue: ImageImageSimilarityViewModel(services: services))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 图片选择区域
                imageSelectionSection
                
                // 计算按钮
                computeButton
                
                // 结果显示
                resultSection
            }
            .padding()
        }
        .navigationTitle("图图相似度")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPHPicker1) {
            PHPickerWrapper(isPresented: $showPHPicker1, selectionLimit: 1) { items in
                if let item = items.first, let uiImage = UIImage(data: item.imageData) {
                    viewModel.selectedImage1 = uiImage
                }
            }
        }
        .sheet(isPresented: $showPHPicker2) {
            PHPickerWrapper(isPresented: $showPHPicker2, selectionLimit: 1) { items in
                if let item = items.first, let uiImage = UIImage(data: item.imageData) {
                    viewModel.selectedImage2 = uiImage
                }
            }
        }
    }
    
    // MARK: - 图片选择区域
    
    @ViewBuilder
    private var imageSelectionSection: some View {
        HStack(spacing: 12) {
            // 第一张图片
            imageSlot(
                image: viewModel.selectedImage1,
                title: "图片 1",
                showPicker: $showPHPicker1
            )
            
            // VS 分隔
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text("VS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)
            
            // 第二张图片
            imageSlot(
                image: viewModel.selectedImage2,
                title: "图片 2",
                showPicker: $showPHPicker2
            )
        }
    }
    
    @ViewBuilder
    private func imageSlot(
        image: UIImage?,
        title: String,
        showPicker: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let image = image {
                // 已选择图片
                VStack(spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipped()
                        .cornerRadius(12)
                    
                    Button("更换") {
                        showPicker.wrappedValue = true
                    }
                    .font(.caption)
                }
            } else {
                // 未选择图片
                Button {
                    showPicker.wrappedValue = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        
                        Text("选择图片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 140, height: 140)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - 计算按钮
    
    @ViewBuilder
    private var computeButton: some View {
        Button(action: {
            Task {
                await viewModel.computeSimilarity()
            }
        }) {
            HStack {
                if case .initializing = viewModel.state {
                    ProgressView()
                        .tint(.white)
                    Text("初始化服务...")
                        .font(.subheadline)
                } else if case .loading = viewModel.state {
                    ProgressView()
                        .tint(.white)
                    Text("计算中...")
                        .font(.subheadline)
                } else {
                    Image(systemName: "waveform.path")
                    Text("计算相似度")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(viewModel.selectedImage1 == nil || viewModel.selectedImage2 == nil)
        .opacity(viewModel.selectedImage1 == nil || viewModel.selectedImage2 == nil ? 0.5 : 1)
    }
    
    // MARK: - 结果显示
    
    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
            
        case .initializing:
            EmptyView() // 按钮上显示初始化状态
            
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在计算相似度...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
        case .loaded(let similarity):
            VStack(spacing: 16) {
                // 相似度分数
                ZStack {
                    Circle()
                        .stroke(
                            Color.blue.opacity(0.2),
                            lineWidth: 12
                        )
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, similarity)))
                        .stroke(
                            Color.blue,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: similarity)
                    
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f%%", similarity * 100))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("相似度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 150, height: 150)
                
                // 描述
                Text(similarityDescription(for: similarity))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // 重新计算按钮
                Button("重新计算") {
                    viewModel.reset()
                }
                .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                
                Text("计算失败")
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
    
    // MARK: - 辅助方法
    
    private func similarityDescription(for score: Float) -> String {
        switch score {
        case 0.8...:
            return "两张图片高度相似，可能是同一场景或相似内容"
        case 0.6..<0.8:
            return "两张图片较为相似，有明显共同特征"
        case 0.4..<0.6:
            return "两张图片有一定相似性，可能包含相关元素"
        case 0.2..<0.4:
            return "两张图片相似度较低，共同特征较少"
        default:
            return "两张图片几乎不相似"
        }
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
        ImageImageSimilarityView(services: services)
    }
}
