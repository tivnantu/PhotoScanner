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

// MARK: - EmbeddingService

actor EmbeddingService {

    // MARK: - 依赖

    private let plugin: ModelPlugin

    // MARK: - 状态

    private(set) var isReady = false

    // MARK: - 初始化

    init(plugin: ModelPlugin) {
        self.plugin = plugin
    }

    // MARK: - 生命周期

    /// 初始化服务：加载底层模型
    func initialize() async throws {
        guard !isReady else { return }

        let name = plugin.descriptor.displayName
        Logger.model.info("EmbeddingService 初始化中...")
        try await plugin.load()
        isReady = true
        Logger.model.info("EmbeddingService 就绪 (\(name))")
    }

    /// 关闭服务：释放模型资源
    func shutdown() async {
        await plugin.unload()
        isReady = false
        Logger.model.info("EmbeddingService 已关闭")
    }

    // MARK: - 编码

    /// 将图像编码为 embedding 向量
    ///
    /// - Parameter imageData: 原始图像数据（JPEG/PNG 等）
    /// - Returns: 归一化后的 embedding 向量
    func embedImage(_ imageData: Data) async throws -> [Float] {
        try ensureReady()

        let raw = try await plugin.encodeImage(imageData)
        return normalize(raw)
    }

    /// 将文本编码为 embedding 向量
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 归一化后的 embedding 向量
    func embedText(_ text: String) async throws -> [Float] {
        try ensureReady()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PSError.invalidInput("文本不能为空")
        }

        let raw = try await plugin.encodeText(text)
        return normalize(raw)
    }

    // MARK: - 内部工具

    /// 检查服务是否就绪
    private func ensureReady() throws {
        guard isReady else {
            throw PSError.inferenceFailed("EmbeddingService 未初始化，请先调用 initialize()")
        }
    }

    /// L2 归一化
    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
