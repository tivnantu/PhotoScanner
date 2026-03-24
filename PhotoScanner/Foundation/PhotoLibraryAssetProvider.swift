import Foundation
import Photos
import UIKit
import OSLog
import os.lock
import MobileCoreServices

// TODO: 架构合规 - Foundation 层禁止导入 UIKit/Photos，此文件应移至 Infrastructure/ 层
// Issue: Foundation 层应为纯 Swift，零外部依赖
// 迁移目标: Infrastructure/PhotoLibraryAssetProvider.swift

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

        let accessState = currentAccessState()
        guard accessState.hasReadAccess else {
            Logger.vision.warning("previewResource: 权限不可用")
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
            Logger.vision.warning("previewResource: 资源不存在 \(self.shortIdentifier(localIdentifier))")
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(self.shortIdentifier(localIdentifier)) 资源不存在")
            return nil
        }

        // 使用 PHImageManager 直接请求缩略图（更可靠）
        let previewData = await requestThumbnailData(for: asset)

        guard let data = previewData else {
            Logger.vision.warning("previewResource: 缩略图请求失败 \(self.shortIdentifier(localIdentifier))")
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(self.shortIdentifier(localIdentifier)) 缩略图请求失败")
            return nil
        }

        // 写入缓存
        if let cache = thumbnailCache, let image = UIImage(data: data) {
            await cache.store(image, for: localIdentifier)
        }

        await recordPerformance(
            .photoLibraryPreview,
            startedAt: startedAt,
            detail: "\(shortIdentifier(localIdentifier)) 已读取缩略图"
        )

        return PhotoLibraryPreviewResource(
            displayTitle: displayTitle(for: asset),
            previewData: data
        )
    }

    /// 请求缩略图数据（使用 PHImageManager，参考 V1 实现）
    private func requestThumbnailData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat  // 索引构建需要高质量
            options.isNetworkAccessAllowed = true      // 支持 iCloud 下载
            options.resizeMode = .exact

            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            let identifier = asset.localIdentifier

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),  // V1 使用 300x300
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // 跳过 degraded 图，等待高质量图
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false

                // degraded 且无错误时继续等待
                if isDegraded && error == nil && !isCancelled { return }

                // 防止 double-resume
                guard hasResumed.withLock({ val in
                    guard !val else { return false }
                    val = true
                    return true
                }) else { return }

                if isCancelled {
                    Logger.vision.warning("缩略图请求取消: \(String(identifier.prefix(24)))")
                    continuation.resume(returning: nil)
                } else if let error = error {
                    Logger.vision.warning("缩略图请求错误: \(error.localizedDescription), iCloud: \(isInCloud)")
                    continuation.resume(returning: nil)
                } else if let image = image {
                    continuation.resume(returning: image.jpegData(compressionQuality: 0.8))
                } else {
                    Logger.vision.warning("缩略图请求无结果: \(String(identifier.prefix(24))), iCloud: \(isInCloud)")
                    continuation.resume(returning: nil)
                }
            }
        }
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

    /// 获取用于索引的优化尺寸图片（224x224，匹配模型输入）
    /// 使用 ThumbnailCache + ImageIO 降采样，比原图快 10-50 倍，内存占用更低
    func indexOptimizedImageData(for localIdentifier: String, targetSize: Int = 224) async -> Data? {
        let startedAt = ContinuousClock.now
        guard !localIdentifier.isEmpty else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "图片标识为空")
            return nil
        }

        let accessState = currentAccessState()
        guard accessState.hasReadAccess else {
            Logger.vision.warning("indexOptimizedImageData: 权限不可用")
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 权限不可用")
            return nil
        }

        // 优先从 ThumbnailCache 获取（搜索结果可能已经缓存）
        if let cache = thumbnailCache, let cachedImage = await cache.image(for: localIdentifier) {
            // 缓存命中：UIImage → JPEG Data（质量 0.9）
            if let jpegData = cachedImage.jpegData(compressionQuality: 0.9) {
                await recordPerformance(
                    .photoLibraryPreview,
                    startedAt: startedAt,
                    detail: "\(shortIdentifier(localIdentifier)) 缓存命中，大小: \(jpegData.count) bytes"
                )
                return jpegData
            }
        }

        guard let asset = fetchAsset(localIdentifier: localIdentifier) else {
            Logger.vision.warning("indexOptimizedImageData: 资源不存在 \(self.shortIdentifier(localIdentifier))")
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(self.shortIdentifier(localIdentifier)) 资源不存在")
            return nil
        }

        // 使用 requestImage（支持 iCloud）替代 requestImageDataAndOrientation
        // 参考 V1 实现和 previewResource 方法
        let image = await requestImageForIndex(asset: asset, targetSize: targetSize)

        guard let image = image else {
            Logger.vision.warning("indexOptimizedImageData: 图片请求失败 \(self.shortIdentifier(localIdentifier))")
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(self.shortIdentifier(localIdentifier)) 图片请求失败")
            return nil
        }

        let data = image.jpegData(compressionQuality: 0.9)
        await recordPerformance(
            .photoLibraryPreview,
            startedAt: startedAt,
            detail: "\(self.shortIdentifier(localIdentifier)) 已获取优化图 \(targetSize)x\(targetSize)"
        )
        return data
    }

    /// 请求索引优化图片（支持 iCloud）
    private func requestImageForIndex(asset: PHAsset, targetSize: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat  // 索引构建需要高质量
            options.isNetworkAccessAllowed = true      // 支持 iCloud 下载
            options.resizeMode = .exact

            let hasResumed = OSAllocatedUnfairLock(initialState: false)
            let identifier = asset.localIdentifier

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetSize, height: targetSize),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // 跳过 degraded 图，等待高质量图
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error

                // degraded 且无错误时继续等待
                if isDegraded && error == nil && !isCancelled { return }

                // 防止 double-resume
                guard hasResumed.withLock({ val in
                    guard !val else { return false }
                    val = true
                    return true
                }) else { return }

                if isCancelled {
                    Logger.vision.warning("索引图片请求取消: \(String(identifier.prefix(24)))")
                    continuation.resume(returning: nil)
                } else if let error = error {
                    Logger.vision.warning("索引图片请求错误: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    Logger.vision.warning("索引图片请求无结果: \(String(identifier.prefix(24)))")
                    continuation.resume(returning: nil)
                }
            }
        }
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
