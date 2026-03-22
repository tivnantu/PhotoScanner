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
import OnnxRuntimeBindings

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

    private var isLoaded = false

    // MARK: - 内部依赖（加载后赋值）

    private var env: ORTEnv?
    private var imageSession: ORTSession?
    private var textSession: ORTSession?
    private var tokenizer: ChineseCLIPTokenizer?

    // MARK: - 模型常量（与 Python 导出严格一致）

    /// 图像归一化均值（RGB 通道）
    nonisolated static let imageMean: [Float] = [0.48145466, 0.4578275, 0.40821073]

    /// 图像归一化标准差（RGB 通道）
    nonisolated static let imageStd: [Float] = [0.26862954, 0.26130258, 0.27577711]

    /// 图像输入尺寸
    nonisolated static let imageSize: Int = 224

    /// 文本最大 token 长度（含 [CLS] 和 [SEP]）
    nonisolated static let contextLength: Int = 52

    /// ONNX 输入输出名称
    enum OnnxIO {
        nonisolated static let imageInput = "image"
        nonisolated static let imageOutput = "unnorm_image_features"
        nonisolated static let textInput = "text"
        nonisolated static let textOutput = "unnorm_text_features"
    }

    // MARK: - 生命周期

    func load() async throws {
        guard !isLoaded else { return }

        let name = descriptor.displayName
        Logger.model.info("开始加载 \(name)...")

        do {
            let imagePath = try BundleResource.imageEncoderPath()
            let textPath = try BundleResource.textEncoderPath()
            let vocabPath = try BundleResource.vocabPath()

            let env = try ORTEnv(loggingLevel: .warning)
            let sessionOptions = try ORTSessionOptions()
            try sessionOptions.setLogSeverityLevel(.warning)
            try sessionOptions.setIntraOpNumThreads(0)
            try sessionOptions.setLogID("ChineseCLIP")

            let imageSession = try ORTSession(env: env, modelPath: imagePath, sessionOptions: sessionOptions)
            let textSession = try ORTSession(env: env, modelPath: textPath, sessionOptions: sessionOptions)
            let tokenizer = try ChineseCLIPTokenizer(vocabPath: vocabPath, contextLength: descriptor.contextLength)

            self.env = env
            self.imageSession = imageSession
            self.textSession = textSession
            self.tokenizer = tokenizer
            self.isLoaded = true

            Logger.model.info("\(name) 加载完成")
        } catch let error as PSError {
            await unload()
            Logger.model.error("\(name) 加载失败 — \(error.localizedDescription)")
            throw error
        } catch {
            await unload()
            Logger.model.error("\(name) 加载失败 — \(error.localizedDescription)")
            throw PSError.modelLoadFailed(error.localizedDescription)
        }
    }

    func unload() async {
        imageSession = nil
        textSession = nil
        tokenizer = nil
        env = nil
        isLoaded = false

        let name = descriptor.displayName
        Logger.model.info("\(name) 已卸载")
    }

    // MARK: - 编码

    func encodeImage(_ imageData: Data) async throws -> [Float] {
        let imageSession = try requireImageSession()
        let imageTensor = try ChineseCLIPImagePreprocessor.preprocess(imageData: imageData)

        let inputValue = try makeTensorValue(
            from: imageTensor,
            elementType: .float,
            shape: [1, 3, descriptor.imageSize, descriptor.imageSize]
        )

        let outputs = try imageSession.run(
            withInputs: [OnnxIO.imageInput: inputValue],
            outputNames: [OnnxIO.imageOutput],
            runOptions: nil
        )

        let vector = try extractFloatVector(
            from: outputs,
            outputName: OnnxIO.imageOutput,
            expectedLength: descriptor.embeddingDimension
        )

        Logger.model.debug("图像编码完成，维度: \(vector.count)")
        return vector
    }

    func encodeText(_ text: String) async throws -> [Float] {
        let textSession = try requireTextSession()
        let tokenizer = try requireTokenizer()
        let tokenIDs = tokenizer.encodeToInt64(text)

        let inputValue = try makeTensorValue(
            from: tokenIDs,
            elementType: .int64,
            shape: [1, descriptor.contextLength]
        )

        let outputs = try textSession.run(
            withInputs: [OnnxIO.textInput: inputValue],
            outputNames: [OnnxIO.textOutput],
            runOptions: nil
        )

        let vector = try extractFloatVector(
            from: outputs,
            outputName: OnnxIO.textOutput,
            expectedLength: descriptor.embeddingDimension
        )

        Logger.model.debug("文本编码完成，维度: \(vector.count)")
        return vector
    }

    // MARK: - 内部依赖检查

    private func requireImageSession() throws -> ORTSession {
        guard isLoaded, let imageSession else {
            throw PSError.inferenceFailed("图像模型未加载")
        }
        return imageSession
    }

    private func requireTextSession() throws -> ORTSession {
        guard isLoaded, let textSession else {
            throw PSError.inferenceFailed("文本模型未加载")
        }
        return textSession
    }

    private func requireTokenizer() throws -> ChineseCLIPTokenizer {
        guard isLoaded, let tokenizer else {
            throw PSError.inferenceFailed("Tokenizer 未加载")
        }
        return tokenizer
    }

    // MARK: - ORT helper

    private func makeTensorValue<T>(
        from values: [T],
        elementType: ORTTensorElementDataType,
        shape: [Int]
    ) throws -> ORTValue {
        let tensorData = makeMutableData(from: values)
        let tensorShape = shape.map { NSNumber(value: $0) }
        return try ORTValue(tensorData: tensorData, elementType: elementType, shape: tensorShape)
    }

    private func makeMutableData<T>(from values: [T]) -> NSMutableData {
        guard !values.isEmpty else { return NSMutableData() }

        return values.withUnsafeBufferPointer { buffer in
            NSMutableData(
                bytes: buffer.baseAddress,
                length: buffer.count * MemoryLayout<T>.stride
            )
        }
    }

    private func extractFloatVector(
        from outputs: [String: ORTValue],
        outputName: String,
        expectedLength: Int
    ) throws -> [Float] {
        guard let outputValue = outputs[outputName] else {
            throw PSError.inferenceFailed("未找到输出: \(outputName)")
        }

        let tensorData = try outputValue.tensorData()
        let data = Data(referencing: tensorData)
        let values = data.withUnsafeBytes { rawBuffer -> [Float] in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }

        guard values.count >= expectedLength else {
            throw PSError.inferenceFailed("输出长度异常: 期望至少 \(expectedLength)，实际 \(values.count)")
        }

        if values.count == expectedLength {
            return values
        }

        return Array(values.prefix(expectedLength))
    }
}
