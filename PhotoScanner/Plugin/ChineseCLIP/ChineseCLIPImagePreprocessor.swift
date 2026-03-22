//
// ChineseCLIPImagePreprocessor.swift
// PhotoScanner
//
// 图像预处理：将原始图像转换为模型期望的 tensor 格式。
// 流水线：Resize (Bicubic) → CenterCrop → RGB Float [0,1] → Normalize → CHW
//
// 参数来源：docs/context/MODEL_SPECS.md
//

import Foundation
import CoreGraphics
import OSLog

enum ChineseCLIPImagePreprocessor {

    /// 将原始图像数据预处理为模型输入 tensor
    ///
    /// - Parameters:
    ///   - imageData: 原始图像的 Data（JPEG/PNG 等）
    ///   - targetSize: 目标尺寸（默认 224）
    ///   - mean: 归一化均值（RGB）
    ///   - std: 归一化标准差（RGB）
    /// - Returns: [3, targetSize, targetSize] 的 Float 数组（CHW 格式）
    static func preprocess(
        imageData: Data,
        targetSize: Int = ChineseCLIPPlugin.imageSize,
        mean: [Float] = ChineseCLIPPlugin.imageMean,
        std: [Float] = ChineseCLIPPlugin.imageStd
    ) throws -> [Float] {

        // TODO: Phase1 实现以下步骤：

        // 1. Data → CGImage
        // guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
        //       let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        //     throw PSError.invalidInput("无法解码图像数据")
        // }

        // 2. Resize 到 targetSize × targetSize (Bicubic 插值)
        //    使用 vImage 或 Core Graphics

        // 3. 提取 RGB 像素 → Float [0, 1]

        // 4. HWC → CHW 转置

        // 5. 按通道 Normalize: pixel = (pixel - mean) / std

        // 6. 返回 [3 * targetSize * targetSize] 的 Float 数组

        Logger.model.debug("图像预处理: 尚未实现")
        throw PSError.inferenceFailed("图像预处理尚未实现")
    }
}
