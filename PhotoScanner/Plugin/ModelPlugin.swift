//
// ModelPlugin.swift
// PhotoScanner
//
// 模型能力协议。
// Engine 层只依赖这个协议，不关心底层是 ONNX / CoreML / 其他实现。
// 所有模型特定常量（mean / std / context_length 等）封装在具体实现内部。
//

import Foundation

// MARK: - 模型描述信息

/// 模型的静态元信息，用于日志、索引校验、UI 展示
struct ModelDescriptor: Sendable {

    /// 模型唯一标识，例如 "chinese-clip-vit-b-16"
    let id: String

    /// 语义版本号
    let version: String

    /// embedding 输出维度
    let embeddingDimension: Int

    /// 图像输入边长（正方形）
    let imageSize: Int

    /// 文本最大 token 长度
    let contextLength: Int

    /// 用于 UI 展示的名称
    let displayName: String
}

// MARK: - 模型能力协议

/// 双塔模型的统一能力接口
///
/// 设计要点：
/// - 接口只接收原始数据（Data / String），预处理在实现内部完成
/// - 输出为未归一化的 embedding，归一化由 Engine 层统一处理
/// - 实现必须是线程安全的（推荐 actor 隔离）
protocol ModelPlugin: Sendable {

    /// 模型的静态描述信息（编译期常量，nonisolated 安全）
    nonisolated var descriptor: ModelDescriptor { get }

    /// 加载模型到内存（可能耗时）
    func load() async throws

    /// 卸载模型，释放资源
    func unload() async

    /// 将图像编码为 embedding 向量（未归一化）
    ///
    /// - Parameter imageData: 原始图像数据
    /// - Returns: 长度为 embeddingDimension 的浮点数组
    func encodeImage(_ imageData: Data) async throws -> [Float]

    /// 将文本编码为 embedding 向量（未归一化）
    ///
    /// - Parameter text: 原始文本字符串
    /// - Returns: 长度为 embeddingDimension 的浮点数组
    func encodeText(_ text: String) async throws -> [Float]
}
