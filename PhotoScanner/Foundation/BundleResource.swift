//
// BundleResource.swift
// PhotoScanner
//
// Bundle 内资源定位。
// 当前阶段只处理少量固定模型资源，采用最直接、最确定的查找方式。
//

import Foundation
import OSLog

enum BundleResource {

    /// 在 bundle 根目录中定位必需资源，找不到时抛出明确错误。
    nonisolated static func requiredPath(
        forResource name: String,
        withExtension ext: String,
        bundle: Bundle = .main
    ) throws -> String {
        guard let path = bundle.path(forResource: name, ofType: ext) else {
            Logger.app.error("Bundle 资源未找到: \(name).\(ext)")
            throw PSError.resourceNotFound(
                name: name,
                extension: ext,
                subdirectory: nil
            )
        }
        return path
    }

    /// 当前工程中的模型资源通过 target membership 打入 app bundle 根目录。
    nonisolated static func imageEncoderPath() throws -> String {
        try requiredPath(forResource: "image_encoder", withExtension: "onnx")
    }

    nonisolated static func textEncoderPath() throws -> String {
        try requiredPath(forResource: "text_encoder", withExtension: "onnx")
    }

    nonisolated static func vocabPath() throws -> String {
        try requiredPath(forResource: "vocab", withExtension: "txt")
    }
}
