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

    private struct RuntimeContext {
        let env: ORTEnv
        let imageSession: ORTSession
        let textSession: ORTSession
        let tokenizer: ChineseCLIPTokenizer
    }

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

    private var runtime: RuntimeContext?
    private var loadTask: Task<RuntimeContext, Error>?

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
        if runtime != nil {
            return
        }

        if let loadTask {
            let loadedRuntime = try await loadTask.value
            runtime = loadedRuntime
            return
        }

        let name = descriptor.displayName
        Logger.model.info("开始加载 \(name)...")

        let contextLength = descriptor.contextLength
        let task = Task<RuntimeContext, Error> {
            try Self.createRuntimeContext(contextLength: contextLength)
        }
        loadTask = task

        do {
            let loadedRuntime = try await task.value
            runtime = loadedRuntime
            loadTask = nil
            Logger.model.info("\(name) 加载完成")
        } catch let error as PSError {
            runtime = nil
            loadTask = nil
            Logger.model.error("\(name) 加载失败 — \(error.localizedDescription)")
            throw error
        } catch {
            runtime = nil
            loadTask = nil
            let normalizedError = PSError.modelLoadFailed("\(name) 初始化失败：\(error.localizedDescription)")
            Logger.model.error("\(name) 加载失败 — \(normalizedError.localizedDescription)")
            throw normalizedError
        }
    }

    func unload() async {
        runtime = nil
        loadTask = nil
        Logger.model.info("\(self.descriptor.displayName) 已卸载")
    }

    // MARK: - 编码

    func encodeImage(_ imageData: Data) async throws -> [Float] {
        guard !imageData.isEmpty else {
            throw PSError.invalidInput("图像数据不能为空")
        }

        let runtime = try requireRuntime()

        do {
            let imageTensor = try ChineseCLIPImagePreprocessor.preprocess(imageData: imageData)
            let inputValue = try makeTensorValue(
                from: imageTensor,
                elementType: .float,
                shape: [1, 3, descriptor.imageSize, descriptor.imageSize]
            )

            let outputs = try runtime.imageSession.run(
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
        } catch let error as PSError {
            throw error
        } catch {
            throw PSError.inferenceFailed("图像编码失败：\(error.localizedDescription)")
        }
    }

    func encodeText(_ text: String) async throws -> [Float] {
        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            throw PSError.invalidInput("文本不能为空")
        }

        let runtime = try requireRuntime()

        do {
            let tokenIDs = runtime.tokenizer.encodeToInt64(sanitizedText)
            let inputValue = try makeTensorValue(
                from: tokenIDs,
                elementType: .int64,
                shape: [1, descriptor.contextLength]
            )

            let outputs = try runtime.textSession.run(
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
        } catch let error as PSError {
            throw error
        } catch {
            throw PSError.inferenceFailed("文本编码失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 内部依赖检查

    private func requireRuntime() throws -> RuntimeContext {
        if let runtime {
            return runtime
        }

        if loadTask != nil {
            throw PSError.serviceNotReady(
                service: descriptor.displayName,
                reason: "模型仍在加载中，请稍后重试"
            )
        }

        throw PSError.serviceNotReady(
            service: descriptor.displayName,
            reason: "模型尚未加载"
        )
    }

    // MARK: - ORT helper

    nonisolated private static func createRuntimeContext(contextLength: Int) throws -> RuntimeContext {
        let imagePath = try BundleResource.imageEncoderPath()
        let textPath = try BundleResource.textEncoderPath()
        let vocabPath = try BundleResource.vocabPath()

        let env = try ORTEnv(loggingLevel: .warning)
        let sessionOptions = try makeSessionOptions(logID: "ChineseCLIP")
        let imageSession = try ORTSession(env: env, modelPath: imagePath, sessionOptions: sessionOptions)
        let textSession = try ORTSession(env: env, modelPath: textPath, sessionOptions: sessionOptions)
        let tokenizer = try ChineseCLIPTokenizer(vocabPath: vocabPath, contextLength: contextLength)

        return RuntimeContext(
            env: env,
            imageSession: imageSession,
            textSession: textSession,
            tokenizer: tokenizer
        )
    }

    nonisolated private static func makeSessionOptions(logID: String) throws -> ORTSessionOptions {
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setLogSeverityLevel(.warning)
        try sessionOptions.setIntraOpNumThreads(0)
        try sessionOptions.setLogID(logID)
        return sessionOptions
    }

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
            throw PSError.invalidModelOutput("未找到输出: \(outputName)")
        }

        let tensorData = try outputValue.tensorData()
        let data = Data(referencing: tensorData)
        let values = data.withUnsafeBytes { rawBuffer -> [Float] in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }

        guard values.count >= expectedLength else {
            throw PSError.invalidModelOutput(
                "输出长度异常：期望至少 \(expectedLength)，实际 \(values.count)"
            )
        }

        if values.count == expectedLength {
            return values
        }

        return Array(values.prefix(expectedLength))
    }
}
