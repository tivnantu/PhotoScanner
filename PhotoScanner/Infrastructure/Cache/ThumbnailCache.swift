//
// ThumbnailCache.swift
// PhotoScanner
//
// 缩略图内存缓存
// 使用 NSCache 后端，系统内存紧张时自动驱逐。
//

import UIKit
import Photos
import os.lock
import OSLog

/// 缩略图内存缓存
///
/// ## 设计
/// - **actor 隔离**：所有状态变更在 actor executor 上串行执行
/// - **NSCache 后端**：系统内存紧张时自动驱逐，无需手动管理
/// - **容量上限**：500 张 / 50 MB（约 100 KB/张，200×200 @2x）
/// - **MemoryMonitor 集成**：收到系统内存警告时主动 removeAllObjects
/// - **预加载**：接受 [SearchResult]，后台批量请求 PHImageManager
///
/// ## 使用示例
/// ```swift
/// let cache = ThumbnailCache()
///
/// // 查询缓存
/// if let image = await cache.image(for: assetId) {
///     // 使用缓存的缩略图
/// }
///
/// // 存入缓存
/// await cache.store(image, for: assetId)
///
/// // 预加载搜索结果
/// await cache.preload(results: searchResults)
/// ```
actor ThumbnailCache {

    // MARK: - Constants

    /// 缩略图请求尺寸（点）
    static let thumbnailSize = CGSize(width: 200, height: 200)

    /// NSCache 最大条目数
    private static let countLimit = 500

    /// NSCache 最大总字节（50 MB）
    private static let costLimit = 50 * 1024 * 1024

    // MARK: - Storage

    /// 主缓存：id → UIImage
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = ThumbnailCache.countLimit
        c.totalCostLimit = ThumbnailCache.costLimit
        return c
    }()

    /// 正在进行的预加载 Task，避免重复请求同一 id
    private var inflightIDs: Set<String> = []

    // MARK: - Init

    /// 创建缩略图缓存
    ///
    /// - Parameter memoryMonitor: 内存监控器（用于注册内存警告回调）
    init(memoryMonitor: MemoryMonitor? = nil) {
        // 在 Task 中注册，避免 actor 初始化期间阻塞
        Task { [weak self] in
            guard let self = self else { return }
            let monitor = memoryMonitor ?? MemoryMonitor()
            await monitor.register(name: "ThumbnailCache") { [weak self] in
                await self?.handleMemoryWarning()
            }
        }
    }

    // MARK: - Public API

    /// 查询缓存
    ///
    /// O(1) 复杂度，不触发网络或 IO。
    ///
    /// - Parameter id: 资源 ID
    /// - Returns: 缓存的图片，未命中返回 nil
    func image(for id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    /// 写入缓存
    ///
    /// cost 按图片字节数估算。
    ///
    /// - Parameters:
    ///   - image: 缩略图
    ///   - id: 资源 ID
    func store(_ image: UIImage, for id: String) {
        let cost = estimatedCost(image)
        cache.setObject(image, forKey: id as NSString, cost: cost)
    }

    /// 移除缓存
    ///
    /// - Parameter id: 资源 ID
    func remove(for id: String) {
        cache.removeObject(forKey: id as NSString)
    }

    /// 清空所有缓存
    func clearAll() {
        cache.removeAllObjects()
        inflightIDs.removeAll()
        Logger.index.info("[ThumbnailCache] 缓存已清空")
    }

    /// 预加载一批资源 ID 的缩略图
    ///
    /// - 已缓存 / 已在飞行中的 id 自动跳过
    /// - 并发度限制为 4，避免瞬间大量 PHImageManager 请求
    /// - 调用方不需要 await，fire-and-forget 即可
    ///
    /// - Parameter assetIds: 资源 ID 数组
    nonisolated func preload(assetIds: [String]) {
        Task {
            await _preload(assetIds: assetIds)
        }
    }

    /// 缓存条目数上限
    var countLimit: Int {
        Self.countLimit
    }

    // MARK: - Private

    private func _preload(assetIds: [String]) async {
        // 过滤：已缓存或正在加载的跳过
        let pending = assetIds.filter { id in
            cache.object(forKey: id as NSString) == nil
                && !inflightIDs.contains(id)
        }
        guard !pending.isEmpty else { return }

        // 标记为飞行中
        pending.forEach { inflightIDs.insert($0) }

        // 并发度 = 4
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for assetId in pending {
                if active >= 4 {
                    await group.next()
                    active -= 1
                }
                group.addTask { [weak self] in
                    await self?.fetchAndStore(assetId: assetId)
                }
                active += 1
            }
        }
    }

    /// 请求单张缩略图并写入缓存
    private func fetchAndStore(assetId: String) async {
        defer {
            inflightIDs.remove(assetId)
        }

        guard let image = await requestThumbnail(for: assetId) else { return }
        store(image, for: assetId)
    }

    /// 内存警告处理
    private func handleMemoryWarning() {
        cache.removeAllObjects()
        inflightIDs.removeAll()
        Logger.index.warning("[ThumbnailCache] 收到内存警告，缓存已清空")
    }

    /// 估算 UIImage 内存占用（字节）
    private func estimatedCost(_ image: UIImage) -> Int {
        let scale = image.scale
        let w = image.size.width * scale
        let h = image.size.height * scale
        // RGBA 4 bytes/pixel
        return Int(w * h * 4)
    }
}

// MARK: - PHImageManager Request

extension ThumbnailCache {

    /// 通过 PHImageManager 请求缩略图
    ///
    /// - Parameter assetId: PHAsset 的 localIdentifier
    /// - Returns: 缩略图图片
    nonisolated func requestThumbnail(for assetId: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast

            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: ThumbnailCache.thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if isCancelled || hasError {
                    guard hasResumed.withLock({ val in
                        guard !val else { return false }
                        val = true; return true
                    }) else { return }
                    continuation.resume(returning: nil)
                    return
                }

                guard let image else { return }
                guard hasResumed.withLock({ val in
                    guard !val else { return false }
                    val = true; return true
                }) else { return }
                continuation.resume(returning: image)
            }
        }
    }
}
