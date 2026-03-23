//
// ImageDownsampler.swift
// PhotoScanner
//
// 图片降采样工具
// 使用 ImageIO 在解码阶段直接降采样，避免峰值内存过高。
//

import UIKit
import ImageIO
import OSLog

/// 图片降采样工具
///
/// 使用 ImageIO 在解码阶段直接降采样，避免将整张大图（可能 20MB+）
/// 完整解码到内存后再缩放。
///
/// ## 内存对比
/// - `UIImage(data:)`: 解码 4000×3000 = 48MB 位图 → 缩放 → 释放原图
/// - `downsample`: 解码时直接输出目标尺寸，峰值内存仅为目标尺寸的位图
///
/// ## 使用示例
/// ```swift
/// // 从文件数据加载缩略图
/// let thumbnailData = try Data(contentsOf: fileURL)
/// let thumbnail = ImageDownsampler.downsample(thumbnailData, maxDimension: 300)
///
/// // 从 PHAsset 加载（配合 PHImageManager）
/// let result = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: nil) { data, _, _, _ in
///     let image = ImageDownsampler.downsample(data ?? Data(), maxDimension: 600)
/// }
/// ```
nonisolated enum ImageDownsampler {

    /// 从 Data 降采样创建 UIImage
    ///
    /// 使用 ImageIO 的 `kCGImageSourceCreateThumbnailFromImageAlways` 选项，
    /// 在解码阶段直接生成目标尺寸的缩略图，避免解码全尺寸图片。
    ///
    /// - Parameters:
    ///   - data: 原始图片数据
    ///   - maxDimension: 最长边最大像素，默认 1200（兼顾显示清晰度和内存）
    /// - Returns: 降采样后的 UIImage，失败时回退到 UIImage(data:)
    static func downsample(_ data: Data, maxDimension: CGFloat = 1200) -> UIImage? {
        // ImageIO 降采样选项
        // - kCGImageSourceShouldCache: false - 不缓存解码后的位图，节省内存
        // - kCGImageSourceCreateThumbnailFromImageAlways: true - 始终创建缩略图
        // - kCGImageSourceCreateThumbnailWithTransform: true - 应用 EXIF 方向变换
        // - kCGImageSourceThumbnailMaxPixelSize: 目标最大尺寸
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // 降采样失败，回退到 UIImage(data:)
            Logger.vision.warning("ImageIO 降采样失败，回退 UIImage(data:)，数据大小: \(data.count / 1024) KB")
            return UIImage(data: data)
        }

        Logger.vision.debug("图片降采样成功: maxDimension=\(maxDimension), outputSize=\(cgImage.width)x\(cgImage.height)")
        return UIImage(cgImage: cgImage)
    }

    /// 从文件 URL 降采样创建 UIImage
    ///
    /// 直接从文件读取，避免先将整个文件加载到内存。
    ///
    /// - Parameters:
    ///   - url: 图片文件 URL
    ///   - maxDimension: 最长边最大像素，默认 1200
    /// - Returns: 降采样后的 UIImage
    static func downsample(from url: URL, maxDimension: CGFloat = 1200) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            Logger.vision.warning("ImageIO 降采样失败，URL: \(url.path)")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
