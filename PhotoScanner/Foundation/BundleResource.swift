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
    nonisolated static func requiredURL(
        forResource name: String,
        withExtension ext: String,
        bundle: Bundle = .main
    ) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            Logger.app.error("Bundle 资源未找到: \(name).\(ext)")
            throw PSError.resourceNotFound(
                name: name,
                extension: ext,
                subdirectory: nil
            )
        }
        return url
    }

    nonisolated static func requiredPath(
        forResource name: String,
        withExtension ext: String,
        bundle: Bundle = .main
    ) throws -> String {
        try requiredURL(forResource: name, withExtension: ext, bundle: bundle).path
    }

    /// 当前工程中的模型资源通过 target membership 打入 app bundle 根目录。
    nonisolated static func imageEncoderURL(bundle: Bundle = .main) throws -> URL {
        try requiredURL(forResource: "image_encoder", withExtension: "onnx", bundle: bundle)
    }

    nonisolated static func imageEncoderPath(bundle: Bundle = .main) throws -> String {
        try imageEncoderURL(bundle: bundle).path
    }

    nonisolated static func textEncoderURL(bundle: Bundle = .main) throws -> URL {
        try requiredURL(forResource: "text_encoder", withExtension: "onnx", bundle: bundle)
    }

    nonisolated static func textEncoderPath(bundle: Bundle = .main) throws -> String {
        try textEncoderURL(bundle: bundle).path
    }

    nonisolated static func vocabURL(bundle: Bundle = .main) throws -> URL {
        try requiredURL(forResource: "vocab", withExtension: "txt", bundle: bundle)
    }

    nonisolated static func vocabPath(bundle: Bundle = .main) throws -> String {
        try vocabURL(bundle: bundle).path
    }

    /// 为索引 manifest 生成资源指纹。
    ///
    /// 当前先用文件名 + 大小 + 修改时间组合成稳定指纹，避免在端上对大模型文件做整文件哈希。
    nonisolated static func resourceFingerprint(bundle: Bundle = .main) throws -> String {
        let urls = [
            try imageEncoderURL(bundle: bundle),
            try textEncoderURL(bundle: bundle),
            try vocabURL(bundle: bundle)
        ]

        let parts = try urls.map { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modifiedAt = (attributes[.modificationDate] as? Date) ?? .distantPast
            return "\(url.lastPathComponent):\(fileSize):\(Int64(modifiedAt.timeIntervalSince1970))"
        }

        return parts.joined(separator: "|")
    }
}
