import Foundation
import Photos
import UIKit
import OSLog
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

    /// 获取用于索引的优化尺寸图片（224x224，匹配模型输入）
    /// 使用 ThumbnailCache + ImageIO 降采样，比原图快 10-50 倍，内存占用更低
    func indexOptimizedImageData(for localIdentifier: String, targetSize: Int = 224) async -> Data? {
        let startedAt = ContinuousClock.now
        guard !localIdentifier.isEmpty else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "图片标识为空")
            return nil
        }

        guard currentAccessState().hasReadAccess else {
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
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 资源不存在")
            return nil
        }

        // 使用 requestImageDataAndOrientation 获取原始数据，然后用 ImageIO 降采样
        // 避免 UIImage → JPEG → Data 的重复编解码
        let data = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }

        guard let imageData = data else {
            await recordPerformance(.photoLibraryPreview, startedAt: startedAt, detail: "\(shortIdentifier(localIdentifier)) 未获取到数据")
            return nil
        }

        // 使用 ImageIO 降采样到目标尺寸（解码阶段直接缩放，内存最优）
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
        ]

        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            // 降采样失败，返回原始数据（让 preprocessor 处理）
            await recordPerformance(
                .photoLibraryPreview,
                startedAt: startedAt,
                detail: "\(shortIdentifier(localIdentifier)) 降采样失败，使用原始数据 \(imageData.count) bytes"
            )
            return imageData
        }

        // 将降采样后的 CGImage 转为 JPEG Data（去除 Alpha 通道）
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) else {
            return imageData
        }
        
        // JPEG 属性：压缩质量 0.9，不保留元数据以减少大小
        let imageProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: 1 // 正常方向
        ]
        
        // 如果 CGImage 有 Alpha 通道，需要先去除
        let finalImage: CGImage
        if cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst {
            // 创建不透明上下文绘制图像（去除 Alpha）
            let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            // 使用默认位图信息，不指定 byteOrder，让系统决定
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            
            if let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                if let opaqueImage = context.makeImage() {
                    finalImage = opaqueImage
                } else {
                    finalImage = cgImage
                }
            } else {
                // 无法创建上下文，直接使用原图
                finalImage = cgImage
            }
        } else {
            finalImage = cgImage
        }

        CGImageDestinationAddImage(destination, finalImage, imageProperties as CFDictionary)
        CGImageDestinationFinalize(destination)

        let resultData = mutableData as Data

        // 存入 ThumbnailCache（供后续搜索复用）
        if let cache = thumbnailCache, let uiImage = UIImage(data: resultData) {
            await cache.store(uiImage, for: localIdentifier)
        }

        await recordPerformance(
            .photoLibraryPreview,
            startedAt: startedAt,
            detail: "\(shortIdentifier(localIdentifier)) 降采样完成: \(imageData.count) -> \(resultData.count) bytes"
        )
        return resultData
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
