import SwiftUI
import PhotosUI
import Photos
import UIKit

@MainActor
@Observable
class ImageSearchViewModel {
    
    // MARK: - Dependencies
    
    private let embeddingService: EmbeddingService
    private let vectorStore: any VectorStore
    private let photoLibraryAssetProvider: PhotoLibraryAssetProvider
    
    // MARK: - State
    
    var state: ImageSearchState = .idle
    var selectedPreviewImage: UIImage?
    private var hasInitialized = false
    
    // MARK: - Initialization
    
    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.vectorStore = services.vectorStore
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
    }
    
    /// 初始化服务
    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        // 初始化 EmbeddingService
        do {
            try await embeddingService.initialize()
        } catch {
            state = .error(error)
        }
    }
    
    // MARK: - Public Methods
    
    /// 选择图片并开始搜索（通过 Asset ID）
    func selectImage(assetId: String?) async {
        state = .selectingImage
        
        // 1. 获取 Asset ID
        guard let assetId = assetId else {
            // 没有 Asset ID，需要原图数据
            state = .error(ImageSearchError.failedToLoadImage)
            return
        }
        
        // 2. 检查索引中是否已有 embedding
        do {
            if let cachedEmbedding = try await vectorStore.getEmbedding(for: assetId) {
                // 使用缓存 embedding
                await performSearch(with: cachedEmbedding)
            } else {
                // 没有缓存，需要原图数据
                state = .error(ImageSearchError.failedToLoadImage)
            }
        } catch {
            state = .error(error)
        }
    }
    
    /// 使用图片数据进行搜索
    func searchWithImageData(_ data: Data) async {
        // 更新预览图
        if let uiImage = UIImage(data: data) {
            selectedPreviewImage = uiImage
        }
        
        // 向量化
        state = .embedding
        do {
            let embedding = try await embeddingService.embedImage(data)
            await performSearch(with: embedding)
        } catch {
            state = .error(error)
        }
    }
    
    /// 执行搜索
    private func performSearch(with embedding: [Float]) async {
        state = .searching
        do {
            // 获取更多候选结果（30张），然后智能过滤
            let allResults = try await vectorStore.search(queryEmbedding: embedding, topK: 30)
            
            // 智能过滤：根据相似度决定展示数量
            let filteredResults = smartFilterResults(allResults)
            
            let searchResults = try await loadThumbnails(for: filteredResults)
            state = .displaying(searchResults)
            
            // 触觉反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            state = .error(error)
            
            // 错误反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    /// 智能过滤搜索结果
    private func smartFilterResults(_ results: [VectorSearchResult]) -> [VectorSearchResult] {
        guard !results.isEmpty else { return [] }
        
        // 规则：
        // 1. 相似度 >= 0.8：全部展示（最多25张）
        // 2. 相似度 >= 0.6：展示前20张
        // 3. 相似度 < 0.6：展示前15张
        
        let highSimilarityResults = results.filter { $0.score >= 0.8 }
        
        if !highSimilarityResults.isEmpty {
            // 有高相似度结果，展示所有 >= 0.6 的结果，最多25张
            let qualified = results.filter { $0.score >= 0.6 }
            return Array(qualified.prefix(25))
        } else if results.first?.score ?? 0 >= 0.6 {
            // 中等相似度，展示前20张
            return Array(results.prefix(20))
        } else {
            // 低相似度，展示前15张
            return Array(results.prefix(15))
        }
    }
    
    /// 加载缩略图
    private func loadThumbnails(for results: [VectorSearchResult]) async throws -> [ImageSearchResult] {
        try await withThrowingTaskGroup(of: ImageSearchResult.self) { group in
            for result in results {
                group.addTask {
                    // 从 PhotoLibrary 获取预览资源
                    let previewResource = await self.photoLibraryAssetProvider.previewResource(for: result.assetLocalIdentifier)
                    
                    // 创建缩略图
                    let thumbnail: UIImage
                    if let data = previewResource?.previewData, let image = UIImage(data: data) {
                        thumbnail = image
                    } else {
                        thumbnail = UIImage(systemName: "photo")!
                    }
                    
                    // 从 local identifier 创建 PHAsset（用于后续操作）
                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [result.assetLocalIdentifier], options: nil)
                    guard let asset = fetchResult.firstObject else {
                        throw ImageSearchError.failedToLoadImage
                    }
                    
                    return ImageSearchResult(
                        id: result.assetLocalIdentifier,
                        thumbnail: thumbnail,
                        similarity: result.score,
                        asset: asset
                    )
                }
            }
            
            var imageResults: [ImageSearchResult] = []
            for try await result in group {
                imageResults.append(result)
            }
            return imageResults.sorted { $0.similarity > $1.similarity }
        }
    }
}
