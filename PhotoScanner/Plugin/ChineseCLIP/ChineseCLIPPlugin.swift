//
// ChineseCLIPPlugin.swift
// PhotoScanner
//
// Chinese-CLIP ViT-B/16 的 ONNX Runtime 实现。
// ONNX Runtime 只在此文件和同目录文件中出现，不向外泄露。
//
// 模型参数来源：docs/context/MODEL_SPECS.md
//

import Foundation
import OSLog

// MARK: - ChineseCLIPPlugin

actor ChineseCLIPPlugin: ModelPlugin {

    // MARK: - 模型描述

    nonisolated let descriptor = ModelDescriptor(
        id: "chinese-clip-vit-b-16",
        version: "1.0.0",
        embeddingDimension: 512,
        imageSize: 224,
        contextLength: 52,
        displayName: "Chinese-CLIP ViT-B/16"
    )

    // MARK: - 状态

    var isLoaded = false

    // MARK: - 内部依赖（加载后赋值）

    // TODO: Phase1 实现
    // private var imageSession: ORTSession?
    // private var textSession: ORTSession?
    // private var tokenizer: ChineseCLIPTokenizer?

    // MARK: - 模型常量（与 Python 导出严格一致）

    /// 图像归一化均值（RGB 通道）
    static let imageMean: [Float] = [0.48145466, 0.4578275, 0.40821073]

    /// 图像归一化标准差（RGB 通道）
    static let imageStd: [Float] = [0.26862954, 0.26130258, 0.27577711]

    /// 图像输入尺寸
    static let imageSize: Int = 224

    /// 文本最大 token 长度（含 [CLS] 和 [SEP]）
    static let contextLength: Int = 52

    /// ONNX 输入输出名称
    enum OnnxIO {
        static let imageInput = "image"
        static let imageOutput = "unnorm_image_features"
        static let textInput = "text"
        static let textOutput = "unnorm_text_features"
    }

    // MARK: - 生命周期

    func load() async throws {
        guard !isLoaded else { return }

        let name = descriptor.displayName
        Logger.model.info("开始加载 \(name)...")

        // TODO: Phase1 实现以下步骤：
        // 1. 定位 Bundle 内模型文件
        // 2. 创建 ORTEnv + ORTSessionOptions
        // 3. 加载 image_encoder session
        // 4. 加载 text_encoder session
        // 5. 加载 tokenizer (vocab.txt)

        isLoaded = true
        Logger.model.info("\(name) 加载完成")
    }

    func unload() async {
        // TODO: Phase1 实现资源释放
        isLoaded = false
        let name = descriptor.displayName
        Logger.model.info("\(name) 已卸载")
    }

    // MARK: - 编码

    func encodeImage(_ imageData: Data) async throws -> [Float] {
        guard isLoaded else {
            throw PSError.inferenceFailed("模型未加载")
        }

        // TODO: Phase1 实现以下步骤：
        // 1. Data → CGImage
        // 2. Resize 224×224 (Bicubic)
        // 3. RGB → Float [0,1]
        // 4. HWC → CHW
        // 5. Normalize(mean, std)
        // 6. ORTSession.run → [512] float

        throw PSError.inferenceFailed("encodeImage 尚未实现")
    }

    func encodeText(_ text: String) async throws -> [Float] {
        guard isLoaded else {
            throw PSError.inferenceFailed("模型未加载")
        }

        // TODO: Phase1 实现以下步骤：
        // 1. tokenize(text) → [52] int64
        // 2. ORTSession.run → [512] float

        throw PSError.inferenceFailed("encodeText 尚未实现")
    }
}
