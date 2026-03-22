//
// EmptyModelPlugin.swift
// PhotoScanner
//
// 空模型插件：初始化失败时的 fallback，以及 SwiftUI Preview 的默认值。
// 所有编码方法都会抛出明确的错误，不会静默返回空结果。
//

import Foundation

// MARK: - EmptyModelPlugin

actor EmptyModelPlugin: ModelPlugin {

    nonisolated let descriptor = ModelDescriptor(
        id: "empty",
        version: "0.0.0",
        embeddingDimension: 0,
        imageSize: 0,
        contextLength: 0,
        displayName: "Empty (Fallback)"
    )

    var isLoaded = false

    func load() async throws {
        isLoaded = true
    }

    func unload() async {
        isLoaded = false
    }

    func encodeImage(_ imageData: Data) async throws -> [Float] {
        throw PSError.inferenceFailed("EmptyModelPlugin 不支持图像编码")
    }

    func encodeText(_ text: String) async throws -> [Float] {
        throw PSError.inferenceFailed("EmptyModelPlugin 不支持文本编码")
    }
}
