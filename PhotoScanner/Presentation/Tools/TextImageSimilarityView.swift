//
// TextImageSimilarityView.swift
// PhotoScanner
//
// 图文相似度计算页面
//

import SwiftUI
import PhotosUI
import OSLog

struct TextImageSimilarityView: View {
    @Environment(\.services) private var services
    
    @State private var viewModel: TextImageSimilarityViewModel
    @State private var showPHPicker = false
    @State private var selectedPickerItems: [PHPickerResultItem] = []
    
    init(services: AppServices) {
        _viewModel = State(initialValue: TextImageSimilarityViewModel(services: services))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 图片选择区域
                imageSection
                
                // 文本输入区域
                textInputSection
                
                // 计算按钮
                computeButton
                
                // 结果显示
                resultSection
            }
            .padding()
        }
        .navigationTitle("图文相似度")
        .navigationBarTitleDisplayMode(.inline)
        .alert("加载失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("确定", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showPHPicker) {
            PHPickerWrapper(
                isPresented: $showPHPicker,
                selectedItems: $selectedPickerItems,
                selectionLimit: 1
            )
        }
        .onChange(of: selectedPickerItems) { _, newItems in
            guard let item = newItems.first else { return }
            if let uiImage = UIImage(data: item.imageData) {
                viewModel.selectedImage = uiImage
            } else {
                viewModel.errorMessage = "图片加载失败，请重试"
            }
            selectedPickerItems = []
        }
    }
    
    // MARK: - 图片选择区域
    
    @ViewBuilder
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择图片")
                .font(.headline)
            
            if let image = viewModel.selectedImage {
                // 已选择图片
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                    
                    Button("更换图片") {
                        showPHPicker = true
                    }
                    .font(.subheadline)
                }
            } else {
                // 未选择图片
                Button {
                    showPHPicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("点击选择图片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - 文本输入区域
    
    @ViewBuilder
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文本描述")
                .font(.headline)
            
            TextEditor(text: $viewModel.inputText)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
            
            if viewModel.inputText.isEmpty {
                Text("例如：一只橙色的猫在阳光下睡觉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .disabled(viewModel.selectedImage == nil || viewModel.inputText.isEmpty)
        .opacity(viewModel.selectedImage == nil || viewModel.inputText.isEmpty ? 0.5 : 1)
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
            return "图片与文本描述高度匹配，内容非常一致"
        case 0.6..<0.8:
            return "图片与文本描述较为匹配，主要内容一致"
        case 0.4..<0.6:
            return "图片与文本描述有一定关联，但匹配度中等"
        case 0.2..<0.4:
            return "图片与文本描述关联较弱，匹配度较低"
        default:
            return "图片与文本描述几乎不相关"
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
        TextImageSimilarityView(services: services)
    }
}
