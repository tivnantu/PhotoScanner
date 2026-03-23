import SwiftUI
import Photos

/// 图搜图搜索结果
struct ImageSearchResult: Identifiable {
    let id: String              // Asset ID
    let thumbnail: UIImage      // 缩略图
    let similarity: Float       // 相似度 [0, 1]
    let asset: PHAsset          // 原始资产
}

/// 图搜图状态
enum ImageSearchState: Equatable {
    case idle                                   // 空闲
    case selectingImage                         // 选择图片中
    case embedding                              // 向量化中
    case searching                              // 搜索中
    case displaying([ImageSearchResult])        // 展示结果
    case error(Error)                           // 错误
    
    static func == (lhs: ImageSearchState, rhs: ImageSearchState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.selectingImage, .selectingImage):
            return true
        case (.embedding, .embedding):
            return true
        case (.searching, .searching):
            return true
        case (.displaying(let lhsResults), .displaying(let rhsResults)):
            return lhsResults.map { $0.id } == rhsResults.map { $0.id }
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

/// 图搜图错误类型
enum ImageSearchError: LocalizedError {
    case failedToLoadImage          // 图片加载失败
    case failedToEmbedImage         // 向量化失败
    case failedToSearch             // 搜索失败
    case noIndexFound               // 索引不存在
    
    var errorDescription: String? {
        switch self {
        case .failedToLoadImage:
            return "无法加载图片，请重新选择"
        case .failedToEmbedImage:
            return "图片分析失败，请重试"
        case .failedToSearch:
            return "搜索失败，请重试"
        case .noIndexFound:
            return "请先构建索引"
        }
    }
}
