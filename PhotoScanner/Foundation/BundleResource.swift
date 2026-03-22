//
// BundleResource.swift
// PhotoScanner
//
// Bundle 内资源定位。
// 统一提供类型安全的路径查找，避免散落的 Bundle.main.path(forResource:) 调用。
//

import Foundation
import OSLog

struct BundleResourceDescriptor: Sendable {
    let name: String
    let ext: String
    let subdirectory: String?

    var displayName: String {
        if let subdirectory, !subdirectory.isEmpty {
            return "\(subdirectory)/\(name).\(ext)"
        }
        return "\(name).\(ext)"
    }
}

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
        try path(for: BundleResourceDescriptor(name: name, ext: ext, subdirectory: subdirectory))
    }

    /// 按资源描述定位资源文件，返回完整路径
    nonisolated static func path(for descriptor: BundleResourceDescriptor) throws -> String {
        try url(for: descriptor).path
    }

    /// 在 main bundle 中定位资源文件，返回 URL
    static func url(
        forResource name: String,
        withExtension ext: String,
        subdirectory: String? = nil
    ) throws -> URL {
        try url(for: BundleResourceDescriptor(name: name, ext: ext, subdirectory: subdirectory))
    }

    /// 按资源描述定位资源文件，优先走精确目录，失败后回退到 bundle 内递归搜索
    static func url(for descriptor: BundleResourceDescriptor) throws -> URL {
        if let directURL = Bundle.main.url(
            forResource: descriptor.name,
            withExtension: descriptor.ext,
            subdirectory: descriptor.subdirectory
        ) {
            return directURL
        }

        if let fallbackURL = fallbackSearchURL(for: descriptor) {
            Logger.app.notice("Bundle 资源通过回退搜索命中: \(descriptor.displayName)")
            return fallbackURL
        }

        Logger.app.error("Bundle 资源未找到: \(descriptor.displayName)")
        throw PSError.resourceNotFound(
            name: descriptor.name,
            extension: descriptor.ext,
            subdirectory: descriptor.subdirectory
        )
    }

    private static func fallbackSearchURL(for descriptor: BundleResourceDescriptor) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }

        let targetFileName = "\(descriptor.name).\(descriptor.ext)"
        let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent == targetFileName else { continue }
            return fileURL
        }

        return nil
    }
}

// MARK: - ChineseCLIP 资源路径

extension BundleResource {

    private enum ChineseCLIPResource {
        static let modelSubdirectory = "ModelAssets/ChineseCLIP/ViT-B-16/ONNX/FP32"
        static let vocabSubdirectory = "ModelAssets/ChineseCLIP/ViT-B-16"

        static let imageEncoder = BundleResourceDescriptor(
            name: "image_encoder",
            ext: "onnx",
            subdirectory: modelSubdirectory
        )

        static let textEncoder = BundleResourceDescriptor(
            name: "text_encoder",
            ext: "onnx",
            subdirectory: modelSubdirectory
        )

        static let vocab = BundleResourceDescriptor(
            name: "vocab",
            ext: "txt",
            subdirectory: vocabSubdirectory
        )
    }

    nonisolated static func imageEncoderPath() throws -> String {
        try path(for: ChineseCLIPResource.imageEncoder)
    }

    nonisolated static func textEncoderPath() throws -> String {
        try path(for: ChineseCLIPResource.textEncoder)
    }

    nonisolated static func vocabPath() throws -> String {
        try path(for: ChineseCLIPResource.vocab)
    }
}
