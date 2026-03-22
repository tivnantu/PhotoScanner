//
// BundleResource.swift
// PhotoScanner
//
// Bundle 内资源定位。
// 统一提供类型安全的路径查找，避免散落的 Bundle.main.path(forResource:) 调用。
//

import Foundation
import OSLog

enum BundleResource {

    /// 在 main bundle 中定位资源文件，找不到时抛出 PSError.resourceNotFound
    ///
    /// - Parameters:
    ///   - name: 文件名（不含扩展名）
    ///   - ext: 扩展名
    ///   - subdirectory: 可选子目录路径
    /// - Returns: 资源文件的完整路径
    nonisolated static func path(
        forResource name: String,
        withExtension ext: String,
        subdirectory: String? = nil
    ) throws -> String {
        guard let path = Bundle.main.path(
            forResource: name,
            ofType: ext,
            inDirectory: subdirectory
        ) else {
            Logger.app.error("Bundle 资源未找到: \(name).\(ext), 子目录: \(subdirectory ?? "nil")")
            throw PSError.resourceNotFound(name: name, extension: ext)
        }
        return path
    }

    /// 在 main bundle 中定位资源文件，返回 URL
    static func url(
        forResource name: String,
        withExtension ext: String,
        subdirectory: String? = nil
    ) throws -> URL {
        let filePath = try path(forResource: name, withExtension: ext, subdirectory: subdirectory)
        return URL(fileURLWithPath: filePath)
    }
}

// MARK: - ChineseCLIP 资源路径

extension BundleResource {

    nonisolated static func imageEncoderPath() throws -> String {
        try path(forResource: "image_encoder", withExtension: "onnx")
    }

    nonisolated static func textEncoderPath() throws -> String {
        try path(forResource: "text_encoder", withExtension: "onnx")
    }

    nonisolated static func vocabPath() throws -> String {
        try path(forResource: "vocab", withExtension: "txt")
    }
}
