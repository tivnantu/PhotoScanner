//
// EmbeddingService.swift
// PhotoScanner
//
// Embedding 能力的业务门面。
// 协调 ModelPlugin，对上层提供统一的 embedding 接口。
// 不知道底层是 ONNX 还是 CoreML。
//

import Foundation
import OSLog
import CryptoKit
import os.lock

// MARK: - EmbeddingService

/// Embedding 服务 - 支持并发推理
///
/// ## 并发安全性
/// - embedImage/embedText 方法可并发调用
/// - 状态管理使用 OSAllocatedUnfairLock 保护
/// - 缓存访问通过 actor 隔离
///
final class EmbeddingService: @unchecked Sendable {

    // MARK: - 内部状态

    private enum ServiceState: Sendable {
        case idle
        case loading(Task<Void, Error>)
        case ready
        case failed(PSError)
    }

    // MARK: - 依赖

    private let plugin: ModelPlugin

    /// 图像向量缓存（避免重复计算）- actor 隔离
    private let imageCache: EmbeddingCache

    /// 文本向量缓存（避免重复计算）- actor 隔离
    private let textCache: EmbeddingCache

    // MARK: - 状态（锁保护）

    private let lock = OSAllocatedUnfairLock()
    private var _state: ServiceState = .idle

    var isReady: Bool {
        lock.withLock {
            if case .ready = _state { return true }
            return false
        }
    }

    var modelDescriptor: ModelDescriptor {
        plugin.descriptor
    }

    // MARK: - 初始化

    init(plugin: ModelPlugin) {
        self.plugin = plugin
        self.imageCache = EmbeddingCache(config: .image)
        self.textCache = EmbeddingCache(config: .text)
    }

    // MARK: - 生命周期

    /// 初始化服务：加载底层模型
    func initialize() async throws {
        let currentState = lock.withLock { _state }

        switch currentState {
        case .ready:
            return
        case .loading(let task):
            return try await task.value
        case .idle, .failed:
            let modelName = plugin.descriptor.displayName
            Logger.model.info("EmbeddingService 初始化中 (\(modelName))")

            let task = Task {
                try await plugin.load()
            }
            lock.withLock { _state = .loading(task) }

            do {
                try await task.value
                lock.withLock { _state = .ready }
                Logger.model.info("EmbeddingService 就绪 (\(modelName))")
            } catch {
                let normalizedError = Self.normalize(error, fallback: "EmbeddingService 初始化失败")
                lock.withLock { _state = .failed(normalizedError) }
                Logger.model.error("EmbeddingService 初始化失败 (\(modelName)) — \(normalizedError.localizedDescription)")
                throw normalizedError
            }
        }
    }

    /// 关闭服务：释放模型资源
    func shutdown() async {
        let modelName = plugin.descriptor.displayName

        if case .loading(let task) = lock.withLock({ _state }) {
            _ = try? await task.value
        }

        await plugin.unload()
        lock.withLock { _state = .idle }
        Logger.model.info("EmbeddingService 已关闭 (\(modelName))")
    }

    // MARK: - 编码（并发安全）

    /// 将图像编码为 embedding 向量 - 可并发调用
    ///
    /// - Parameter imageData: 原始图像数据（JPEG/PNG 等）
    /// - Returns: 归一化后的 embedding 向量
    nonisolated func embedImage(_ imageData: Data) async throws -> [Float] {
        try ensureReady()
        guard !imageData.isEmpty else {
            throw PSError.invalidInput("图像数据不能为空")
        }

        // 缓存键：使用 SHA256 哈希
        let cacheKey = Self.cacheKey(for: imageData)

        // 尝试从缓存获取（actor 访问）
        if let cached = await imageCache.get(for: cacheKey) {
            Logger.model.debug("图像 embedding 缓存命中: \(cacheKey.prefix(8))")
            return cached.values
        }

        // 并发推理（plugin.encodeImage 是线程安全的）
        let raw = try await plugin.encodeImage(imageData)
        let validated = try validate(vector: raw, source: "图像 embedding")
        let normalized = try normalize(validated, source: "图像 embedding")

        // 写入缓存
        let embedding = Embedding(values: normalized)
        await imageCache.set(embedding, for: cacheKey)
        Logger.model.debug("图像 embedding 已缓存: \(cacheKey.prefix(8))")

        return normalized
    }

    /// 将文本编码为 embedding 向量 - 可并发调用
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 归一化后的 embedding 向量
    nonisolated func embedText(_ text: String) async throws -> [Float] {
        try ensureReady()

        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            throw PSError.invalidInput("文本不能为空")
        }

        // 缓存键：使用 SHA256 哈希
        let cacheKey = Self.cacheKey(for: sanitizedText)

        // 尝试从缓存获取（actor 访问）
        if let cached = await textCache.get(for: cacheKey) {
            Logger.model.debug("文本 embedding 缓存命中: \(cacheKey.prefix(8))")
            return cached.values
        }

        // 并发推理（plugin.encodeText 是线程安全的）
        let raw = try await plugin.encodeText(sanitizedText)
        let validated = try validate(vector: raw, source: "文本 embedding")
        let normalized = try normalize(validated, source: "文本 embedding")

        // 写入缓存
        let embedding = Embedding(values: normalized)
        await textCache.set(embedding, for: cacheKey)
        Logger.model.debug("文本 embedding 已缓存: \(cacheKey.prefix(8))")

        return normalized
    }

    /// 清除所有缓存
    func clearCache() async {
        await imageCache.clearAll()
        await textCache.clearAll()
        Logger.model.info("EmbeddingService 缓存已清除")
    }

    /// 获取缓存统计信息
    func cacheStats() async -> (imageCount: Int, textCount: Int) {
        let imageCount = await imageCache.memoryCount
        let textCount = await textCache.memoryCount
        return (imageCount, textCount)
    }

    // MARK: - 内部工具

    /// 生成缓存键
    private nonisolated static func cacheKey(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func cacheKey(for text: String) -> String {
        let hash = SHA256.hash(data: text.data(using: .utf8) ?? Data())
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 检查服务是否就绪
    private nonisolated func ensureReady() throws {
        let currentState = lock.withLock { _state }
        switch currentState {
        case .ready:
            return
        case .idle:
            throw PSError.serviceNotReady(
                service: "EmbeddingService",
                reason: "模型尚未初始化，请先调用 initialize()"
            )
        case .loading:
            throw PSError.serviceNotReady(
                service: "EmbeddingService",
                reason: "模型仍在加载中，请稍后重试"
            )
        case .failed(let error):
            throw PSError.serviceNotReady(
                service: "EmbeddingService",
                reason: error.localizedDescription
            )
        }
    }

    private nonisolated func validate(vector: [Float], source: String) throws -> [Float] {
        guard !vector.isEmpty else {
            throw PSError.invalidModelOutput("\(source) 为空")
        }

        let expectedDimension = plugin.descriptor.embeddingDimension
        guard vector.count == expectedDimension else {
            throw PSError.invalidModelOutput(
                "\(source) 维度不匹配，期望 \(expectedDimension)，实际 \(vector.count)"
            )
        }

        return vector
    }

    /// L2 归一化
    private nonisolated func normalize(_ vector: [Float], source: String) throws -> [Float] {
        let result = SimdUtils.normalize(vector)

        // 验证归一化结果
        guard result.allSatisfy(\.isFinite) else {
            throw PSError.invalidModelOutput("\(source) 范数异常，无法归一化")
        }

        return result
    }

    private nonisolated static func normalize(_ error: Error, fallback: String) -> PSError {
        if let psError = error as? PSError {
            return psError
        }
        return .unknown("\(fallback)：\(error.localizedDescription)")
    }
}
