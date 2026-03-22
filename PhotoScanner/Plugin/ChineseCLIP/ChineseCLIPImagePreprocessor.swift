//
// ChineseCLIPImagePreprocessor.swift
// PhotoScanner
//
// 图像预处理：将原始图像转换为模型期望的 tensor 格式。
// 流水线：Resize (224x224) → RGB Float [0,1] → Normalize → CHW
//
// 参数来源：docs/context/MODEL_SPECS.md
// Python 参考：cn_clip/clip/utils.py:image_transform
//

import Foundation
import CoreGraphics
import ImageIO
import OSLog

enum ChineseCLIPImagePreprocessor {

    // MARK: - 公开接口

    /// 将原始图像数据预处理为模型输入 tensor
    ///
    /// - Parameters:
    ///   - imageData: 原始图像的 Data（JPEG/PNG 等）
    ///   - targetSize: 目标尺寸（默认 224）
    ///   - mean: 归一化均值（RGB）
    ///   - std: 归一化标准差（RGB）
    /// - Returns: [3, targetSize, targetSize] 的 Float 数组（CHW 格式）
    nonisolated static func preprocess(
        imageData: Data,
        targetSize: Int = ChineseCLIPPlugin.imageSize,
        mean: [Float] = ChineseCLIPPlugin.imageMean,
        std: [Float] = ChineseCLIPPlugin.imageStd
    ) throws -> [Float] {
        guard targetSize > 0 else {
            throw PSError.invalidInput("targetSize 必须大于 0")
        }
        guard mean.count == 3, std.count == 3 else {
            throw PSError.invalidInput("mean / std 必须是 3 通道")
        }

        let rgbaBytes = try makeRGBABytes(from: imageData, width: targetSize, height: targetSize)
        let chwTensor = makeNormalizedCHWTensor(
            rgbaBytes: rgbaBytes,
            width: targetSize,
            height: targetSize,
            mean: mean,
            std: std
        )

        Logger.model.debug("图像预处理完成: \(targetSize)x\(targetSize)")
        return chwTensor
    }

    // MARK: - RGBA buffer

    nonisolated private static func makeRGBABytes(from imageData: Data, width: Int, height: Int) throws -> [UInt8] {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw PSError.invalidInput("无法解码图像数据")
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var rgbaBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rgbaBytes,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw PSError.inferenceFailed("无法创建图像位图上下文")
        }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return rgbaBytes
    }

    // MARK: - Tensor

    nonisolated private static func makeNormalizedCHWTensor(
        rgbaBytes: [UInt8],
        width: Int,
        height: Int,
        mean: [Float],
        std: [Float]
    ) -> [Float] {
        let planeSize = width * height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var tensor = [Float](repeating: 0, count: planeSize * 3)

        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * bytesPerRow + x * bytesPerPixel
                let pixelIndex = y * width + x

                let r = Float(rgbaBytes[pixelOffset]) / 255.0
                let g = Float(rgbaBytes[pixelOffset + 1]) / 255.0
                let b = Float(rgbaBytes[pixelOffset + 2]) / 255.0

                tensor[pixelIndex] = (r - mean[0]) / std[0]
                tensor[planeSize + pixelIndex] = (g - mean[1]) / std[1]
                tensor[planeSize * 2 + pixelIndex] = (b - mean[2]) / std[2]
            }
        }

        return tensor
    }
}
