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

// MARK: - EmbeddingService

actor EmbeddingService {

    // MARK: - 内部状态

    private enum ServiceState {
        case idle
        case loading(Task<Void, Error>)
        case ready
        case failed(PSError)
    }

    // MARK: - 依赖

    private let plugin: ModelPlugin
    
    /// 图像向量缓存（避免重复计算）
    private let imageCache: EmbeddingCache
    
    /// 文本向量缓存（避免重复计算）
    private let textCache: EmbeddingCache

    // MARK: - 状态

    private var state: ServiceState = .idle

    var isReady: Bool {
        if case .ready = state {
            return true
        }
        return false
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
        switch state {
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
            state = .loading(task)

            do {
                try await task.value
                state = .ready
                Logger.model.info("EmbeddingService 就绪 (\(modelName))")
            } catch {
                let normalizedError = Self.normalize(error, fallback: "EmbeddingService 初始化失败")
                state = .failed(normalizedError)
                Logger.model.error("EmbeddingService 初始化失败 (\(modelName)) — \(normalizedError.localizedDescription)")
                throw normalizedError
            }
        }
    }

    /// 关闭服务：释放模型资源
    func shutdown() async {
        let modelName = plugin.descriptor.displayName

        if case .loading(let task) = state {
            _ = try? await task.value
        }

        await plugin.unload()
        state = .idle
        Logger.model.info("EmbeddingService 已关闭 (\(modelName))")
    }

    // MARK: - 编码

    /// 将图像编码为 embedding 向量
    ///
    /// - Parameter imageData: 原始图像数据（JPEG/PNG 等）
    /// - Returns: 归一化后的 embedding 向量
    func embedImage(_ imageData: Data) async throws -> [Float] {
        try ensureReady()
        guard !imageData.isEmpty else {
            throw PSError.invalidInput("图像数据不能为空")
        }
        
        // 缓存键：使用 SHA256 哈希
        let cacheKey = Self.cacheKey(for: imageData)
        
        // 尝试从缓存获取
        if let cached = await imageCache.get(for: cacheKey) {
            Logger.model.debug("图像 embedding 缓存命中: \(cacheKey.prefix(8))")
            return cached.values
        }

        // 计算并缓存
        let raw = try await plugin.encodeImage(imageData)
        let validated = try validate(vector: raw, source: "图像 embedding")
        let normalized = try normalize(validated, source: "图像 embedding")
        
        // 写入缓存
        let embedding = Embedding(values: normalized)
        await imageCache.set(embedding, for: cacheKey)
        Logger.model.debug("图像 embedding 已缓存: \(cacheKey.prefix(8))")
        
        return normalized
    }

    /// 将文本编码为 embedding 向量
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 归一化后的 embedding 向量
    func embedText(_ text: String) async throws -> [Float] {
        try ensureReady()

        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            throw PSError.invalidInput("文本不能为空")
        }
        
        // 缓存键：使用 SHA256 哈希
        let cacheKey = Self.cacheKey(for: sanitizedText)
        
        // 尝试从缓存获取
        if let cached = await textCache.get(for: cacheKey) {
            Logger.model.debug("文本 embedding 缓存命中: \(cacheKey.prefix(8))")
            return cached.values
        }

        // 计算并缓存
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
    private func ensureReady() throws {
        switch state {
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

    private func validate(vector: [Float], source: String) throws -> [Float] {
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
    private func normalize(_ vector: [Float], source: String) throws -> [Float] {
        let squaredNorm = vector.reduce(Float.zero) { partial, value in
            partial + value * value
        }
        let norm = sqrt(squaredNorm)

        guard norm.isFinite, norm > .ulpOfOne else {
            throw PSError.invalidModelOutput("\(source) 范数异常，无法归一化")
        }

        return vector.map { $0 / norm }
    }

    private static func normalize(_ error: Error, fallback: String) -> PSError {
        if let psError = error as? PSError {
            return psError
        }
        return .unknown("\(fallback)：\(error.localizedDescription)")
    }
}
