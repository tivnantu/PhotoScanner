import Foundation
import Photos
import UIKit

enum PhotoLibraryAccessState: Sendable, Equatable {
    case fullAccess
    case limitedAccess
    case notDetermined
    case unavailable

    var hasReadAccess: Bool {
        switch self {
        case .fullAccess, .limitedAccess:
            return true
        case .notDetermined, .unavailable:
            return false
        }
    }
}

struct PhotoLibraryPreviewResource: Sendable {
    let displayTitle: String
    let previewData: Data?
}

actor PhotoLibraryAssetProvider {
    private let performanceStore: RuntimePerformanceStore
    
    /// 缩略图缓存（可选）
    private let thumbnailCache: ThumbnailCache?

    init(performanceStore: RuntimePerformanceStore, thumbnailCache: ThumbnailCache? = nil) {
        self.performanceStore = performanceStore
        self.thumbnailCache = thumbnailCache
    }

    func currentAccessState() -> PhotoLibraryAccessState {
        Self.accessState(for: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestReadAccessIfNeeded() async -> PhotoLibraryAccessState {
        let currentState = currentAccessState()
        guard !currentState.hasReadAccess else {
            return currentState
        }

        let authorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        return Self.accessState(for: authorizationStatus)
    }

    func previewResource(for localIdentifier: String) async -> PhotoLibraryPreviewResource? {
        let startedAt = ContinuousClock.now
        guard !localIdentifier.isEmpty else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "图片标识为空")
            return nil
        }

        guard currentAccessState().hasReadAccess else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 权限不可用")
            return nil
        }
        
        // 优先从 ThumbnailCache 获取
        if let cache = thumbnailCache, let cachedImage = await cache.image(for: localIdentifier) {
            await recordPerformance(
                .photoLibraryPreview,
                startedAt: startedAt,
                detail: "\(shortIdentifier(localIdentifier)) 缓存命中"
            )
            return PhotoLibraryPreviewResource(
                displayTitle: "", // 缩略图不需要标题
                previewData: cachedImage.pngData()
            )
        }

        guard let asset = fetchAsset(localIdentifier: localIdentifier) else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 资源不存在")
            return nil
        }

        let previewData = await requestImageData(
            for: asset,
            deliveryMode: .fastFormat,
            resizeMode: .fast,
            allowsNetworkAccess: false
        )
        
        // 写入缓存
        if let cache = thumbnailCache, let data = previewData, let image = UIImage(data: data) {
            await cache.store(image, for: localIdentifier)
        }
        
        await recordPerformance(
            .photoLibraryPreview,
            startedAt: startedAt,
            detail: "\(shortIdentifier(localIdentifier)) \(previewData == nil ? "未命中预览" : "已读取预览")"
        )

        return PhotoLibraryPreviewResource(
            displayTitle: displayTitle(for: asset),
            previewData: previewData
        )
    }

    func originalImageData(for localIdentifier: String) async -> Data? {
        let startedAt = ContinuousClock.now
        guard !localIdentifier.isEmpty else {
            await recordPerformance(.photoLibraryOriginal, startedAt: startedAt, detail: "图片标识为空")
            return nil
        }

        guard currentAccessState().hasReadAccess else {
            await recordPerformance(.photoLibraryOriginal, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 权限不可用")
            return nil
        }

        guard let asset = fetchAsset(localIdentifier: localIdentifier) else {
            await recordPerformance(.photoLibraryOriginal, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 原图不存在")
            return nil
        }

        let data = await requestImageData(
            for: asset,
            deliveryMode: .highQualityFormat,
            resizeMode: .none,
            allowsNetworkAccess: false
        )
        await recordPerformance(
            .photoLibraryOriginal,
            startedAt: startedAt,
            detail: "\(shortIdentifier(localIdentifier)) \(data == nil ? "未读到原图" : "已读取原图")"
        )
        return data
    }

    func containsAsset(with localIdentifier: String) -> Bool {
        guard !localIdentifier.isEmpty else { return false }
        guard currentAccessState().hasReadAccess else { return false }
        return fetchAsset(localIdentifier: localIdentifier) != nil
    }

    private func fetchAsset(localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    private nonisolated static func accessState(for status: PHAuthorizationStatus) -> PhotoLibraryAccessState {
        switch status {
        case .authorized:
            return .fullAccess
        case .limited:
            return .limitedAccess
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    private func requestImageData(
        for asset: PHAsset,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode,
        allowsNetworkAccess: Bool
    ) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = resizeMode
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func recordPerformance(
        _ key: RuntimePerformanceMetricKey,
        startedAt: ContinuousClock.Instant,
        detail: String
    ) async {
        await performanceStore.record(key, duration: startedAt.duration(to: .now), detail: detail)
    }

    private func shortIdentifier(_ localIdentifier: String) -> String {
        let prefix = String(localIdentifier.prefix(8))
        return prefix.isEmpty ? "unknown" : prefix
    }

    private func displayTitle(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if let originalFilename = resources.first?.originalFilename, !originalFilename.isEmpty {
            return originalFilename
        }

        if let creationDate = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "系统相册图片 · \(formatter.string(from: creationDate))"
        }

        return "系统相册图片"
    }
}
