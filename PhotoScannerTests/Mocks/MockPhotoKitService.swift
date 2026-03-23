import Foundation
import Photos
import UIKit
@testable import PhotoScanner

/// Mock PhotoKitService for testing
actor MockPhotoKitService {
    var mockAssets: [String: PHAsset] = [:]
    var mockThumbnails: [String: UIImage] = [:]
    
    nonisolated init() {}
    
    func fetchAsset(id: String) async throws -> PHAsset {
        guard let asset = mockAssets[id] else {
            throw ImageSearchError.failedToLoadImage
        }
        return asset
    }
    
    func loadThumbnail(for asset: PHAsset, targetSize: CGSize) async throws -> UIImage {
        guard let thumbnail = mockThumbnails[asset.localIdentifier] else {
            return UIImage(systemName: "photo")!
        }
        return thumbnail
    }
}
