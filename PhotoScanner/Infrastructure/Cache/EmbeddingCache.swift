//
// EmbeddingCache.swift
// PhotoScanner
//
// 嵌入向量统一缓存
// 可配置的双级缓存：内存层 (NSCache) + 磁盘层 (可选)
//

import Foundation
import CryptoKit
import OSLog

/// 嵌入向量统一缓存
///
/// 可配置的双级缓存：
/// - 内存层：NSCache（自动内存管理）
/// - 磁盘层：FileManager 持久化（可选）
///
/// ## 使用示例
/// ```swift
/// let cache = EmbeddingCache(config: .image)
///
/// // 缓存命中
/// if let embedding = await cache.get(for: imageId) {
///     return embedding
/// }
///
/// // 计算并缓存
/// let embedding = try await computeEmbedding(image)
/// await cache.set(embedding, for: imageId)
/// ```
///
/// ## 线程安全
/// 使用 actor 隔离保证并发安全。
actor EmbeddingCache {

    // MARK: - 配置

    /// 缓存配置
    struct CacheConfig: Sendable {
        let memoryCountLimit: Int
        let memoryCostLimit: Int
        let enableDiskCache: Bool
        let diskSubdirectory: String?

        /// 图像向量缓存配置
        static let image = CacheConfig(
            memoryCountLimit: 1000,
            memoryCostLimit: 10 * 1024 * 1024,  // 10 MB
            enableDiskCache: true,
            diskSubdirectory: "embeddings/image"
        )

        /// 文本向量缓存配置
        static let text = CacheConfig(
            memoryCountLimit: 500,
            memoryCostLimit: 5 * 1024 * 1024,  // 5 MB
            enableDiskCache: true,
            diskSubdirectory: "embeddings/text"
        )

        /// 仅内存缓存配置
        static let memoryOnly = CacheConfig(
            memoryCountLimit: 500,
            memoryCostLimit: 5 * 1024 * 1024,
            enableDiskCache: false,
            diskSubdirectory: nil
        )
    }

    // MARK: - Properties

    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskDirectory: URL?
    private let config: CacheConfig

    // MARK: - Init

    /// 创建嵌入向量缓存
    ///
    /// - Parameter config: 缓存配置
    init(config: CacheConfig) {
        self.config = config
        memoryCache.countLimit = config.memoryCountLimit
        memoryCache.totalCostLimit = config.memoryCostLimit

        if config.enableDiskCache, let subdir = config.diskSubdirectory {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                diskDirectory = nil
                return
            }
            diskDirectory = caches.appendingPathComponent(subdir, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: diskDirectory!, withIntermediateDirectories: true)
            } catch {
                Logger.model.error("[EmbeddingCache] 创建磁盘缓存目录失败: \(error.localizedDescription)")
            }
        } else {
            diskDirectory = nil
        }
    }

    // MARK: - Public API

    /// 获取缓存的嵌入向量
    ///
    /// 查找顺序：内存 → 磁盘（如果命中磁盘则回填内存）
    ///
    /// - Parameter key: 缓存键
    /// - Returns: 缓存命中则返回 Embedding，否则 nil
    func get(for key: String) -> Embedding? {
        let nsKey = key as NSString

        // 内存优先
        if let entry = memoryCache.object(forKey: nsKey) {
            return entry.embedding
        }

        // 磁盘回填
        if let embedding = readFromDisk(key: key) {
            let entry = CacheEntry(embedding: embedding)
            memoryCache.setObject(entry, forKey: nsKey, cost: embedding.values.count * 4)
            return embedding
        }

        return nil
    }

    /// 获取缓存的嵌入向量（以 Data 的 SHA256 哈希为 key）
    ///
    /// - Parameter data: 原始数据
    /// - Returns: 缓存命中则返回 Embedding，否则 nil
    func get(for data: Data) -> Embedding? {
        get(for: Self.hashKey(for: data))
    }

    /// 存入嵌入向量
    ///
    /// - Parameters:
    ///   - embedding: 嵌入向量
    ///   - key: 缓存键
    func set(_ embedding: Embedding, for key: String) {
        let nsKey = key as NSString
        let entry = CacheEntry(embedding: embedding)

        memoryCache.setObject(entry, forKey: nsKey, cost: embedding.values.count * 4)
        writeToDisk(embedding: embedding, key: key)
    }

    /// 存入嵌入向量（以 Data 的 SHA256 哈希为 key）
    ///
    /// - Parameters:
    ///   - embedding: 嵌入向量
    ///   - data: 原始数据
    func set(_ embedding: Embedding, for data: Data) {
        set(embedding, for: Self.hashKey(for: data))
    }

    /// 清除所有缓存
    func clearAll() {
        let diskSizeBefore = diskSize
        memoryCache.removeAllObjects()

        if let diskDirectory = diskDirectory {
            do {
                try FileManager.default.removeItem(at: diskDirectory)
                try FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.model.error("[缓存] 清空磁盘缓存失败: \(error.localizedDescription)")
            }
        }

        Logger.model.info("[缓存] 已清空, 释放 \(diskSizeBefore / 1024) KB")
    }

    /// 清除内存缓存
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        Logger.model.info("[缓存] 内存缓存已清空")
    }

    /// 磁盘缓存大小（字节）
    var diskSize: Int64 {
        guard let diskDirectory = diskDirectory else { return 0 }

        let enumerator = FileManager.default.enumerator(at: diskDirectory, includingPropertiesForKeys: [.fileSizeKey])
        var totalSize: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalSize += Int64(size)
        }
        return totalSize
    }

    /// 内存缓存条目数
    ///
    /// TODO: 准确性 - 当前返回配置的限制值，而非实际缓存条目数
    /// 问题：NSCache 不直接提供条目计数，需要额外维护
    /// 建议：考虑维护一个独立的计数器，或使用近似值
    var memoryCount: Int {
        config.memoryCountLimit
    }

    // MARK: - Hashing

    /// 计算数据的 SHA256 哈希作为缓存键
    ///
    /// - Parameter data: 原始数据
    /// - Returns: SHA256 哈希字符串
    nonisolated static func hashKey(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Disk I/O

    private func diskURL(for key: String) -> URL? {
        diskDirectory?.appendingPathComponent(key).appendingPathExtension("emb")
    }

    private func readFromDisk(key: String) -> Embedding? {
        guard let url = diskURL(for: key) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }

        return Embedding(from: data)
    }

    private func writeToDisk(embedding: Embedding, key: String) {
        guard let url = diskURL(for: key) else { return }

        // 确保父目录存在（系统可能清理 Caches 目录）
        let parentDir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            Logger.model.error("[EmbeddingCache] 创建缓存目录失败: \(error.localizedDescription)")
            return
        }

        let data = embedding.toData()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.model.error("[EmbeddingCache] 磁盘缓存写入失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Cache Entry (NSCache wrapper)

private final class CacheEntry: NSObject {
    nonisolated let embedding: Embedding

    nonisolated init(embedding: Embedding) {
        self.embedding = embedding
        super.init()
    }
}
