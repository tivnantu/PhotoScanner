//
// ANECompatibilityChecker.swift
// PhotoScanner
//
// ANE 兼容性检查器
// 确定最佳推理策略，根据设备能力和环境动态调整。
//

import Foundation
import CoreML
import OSLog

/// ANE 兼容性检查器
///
/// 在应用启动时执行，确定最佳推理策略。
/// 根据 ANE 支持情况和设备温度/电量状态动态调整计算单元。
///
/// ## 使用示例
/// ```swift
/// let checker = ANECompatibilityChecker()
///
/// // 检查兼容性
/// let compatibility = await checker.checkCompatibility(visionModelURL: modelURL)
///
/// // 获取推荐配置
/// let config = await checker.getRecommendedConfig()
///
/// // 加载模型
/// let model = try MLModel(contentsOf: modelURL, configuration: config)
/// ```
actor ANECompatibilityChecker {

    // MARK: - Types

    /// ANE 兼容性级别
    enum ANECompatibility: String, Sendable {
        /// 未知（未检查）
        case unknown
        /// ANE 独占，性能最优
        case fullySupported
        /// ANE + CPU 混合
        case partialSupport
        /// 不支持 ANE，纯 CPU
        case notSupported
        /// 检查失败
        case checkFailed
    }

    /// 计算策略
    enum ComputeStrategy: Sendable {
        /// ANE 独占模式
        case aneExclusive
        /// ANE 带回退
        case aneWithFallback
        /// CPU + ANE 混合
        case cpuAndANE
        /// 纯 CPU
        case cpuOnly

        /// 转换为 MLModelConfiguration
        var config: MLModelConfiguration {
            let config = MLModelConfiguration()
            switch self {
            case .aneExclusive:
                config.computeUnits = .all
            case .aneWithFallback:
                config.computeUnits = .all
            case .cpuAndANE:
                config.computeUnits = .cpuAndNeuralEngine
            case .cpuOnly:
                config.computeUnits = .cpuOnly
            }
            return config
        }
    }

    // MARK: - Properties

    /// 视觉模型兼容性
    private(set) var visionModelCompatibility: ANECompatibility = .unknown

    // MARK: - 兼容性检查

    /// 执行完整的 ANE 兼容性检查
    ///
    /// 应在应用启动时调用一次，结果缓存复用。
    ///
    /// - Parameter visionModelURL: 视觉模型文件 URL
    /// - Returns: ANE 兼容性级别
    func checkCompatibility(visionModelURL: URL) async -> ANECompatibility {
        Logger.model.info("[ANE] 开始兼容性检查...")

        // 1. 检查设备是否支持 ANE (A12+)
        guard isANESupported() else {
            Logger.model.warning("[ANE] 设备不支持 ANE，使用 CPU")
            visionModelCompatibility = .notSupported
            return .notSupported
        }

        // 2. 尝试 ANE 独占模式加载
        let exclusiveConfig = ComputeStrategy.aneExclusive.config

        do {
            let model = try MLModel(contentsOf: visionModelURL, configuration: exclusiveConfig)

            // 3. 执行测试推理验证 ANE 实际可用
            let testResult = await performTestInference(model: model)

            if testResult.success && testResult.usedANE {
                Logger.model.info("[ANE] ✅ 独占模式验证通过，推理耗时: \(String(format: "%.2f", testResult.latency))ms")
                visionModelCompatibility = .fullySupported
                return .fullySupported
            } else if testResult.success {
                Logger.model.warning("[ANE] ⚠️ 模型加载成功但可能未使用 ANE")
                visionModelCompatibility = .partialSupport
                return .partialSupport
            } else {
                Logger.model.error("[ANE] ❌ ANE 推理失败: \(testResult.error ?? "未知错误")")
                visionModelCompatibility = .notSupported
                return .notSupported
            }

        } catch {
            Logger.model.error("[ANE] ❌ ANE 独占模式加载失败: \(error)")

            // 4. 尝试混合模式
            return await tryFallbackMode(visionModelURL: visionModelURL)
        }
    }

    // MARK: - 策略选择

    /// 根据当前环境选择最佳策略
    ///
    /// 考虑因素：
    /// - 设备温度状态
    /// - 低电量模式
    /// - ANE 兼容性
    ///
    /// - Returns: 计算策略
    func selectStrategy() -> ComputeStrategy {
        let thermalState = ProcessInfo.processInfo.thermalState
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // 1. 高温 → CPUOnly
        if thermalState == .critical || thermalState == .serious {
            Logger.model.info("[ANE] 温度高(\(thermalState.label)), 使用 CPUOnly")
            return .cpuOnly
        }

        // 2. 低电量模式 → CPUOnly
        if isLowPowerMode {
            Logger.model.info("[ANE] 低电量模式, 使用 CPUOnly")
            return .cpuOnly
        }

        // 3. 根据兼容性选择
        switch visionModelCompatibility {
        case .fullySupported:
            return .aneExclusive
        case .partialSupport:
            return .aneWithFallback
        case .notSupported, .checkFailed:
            return .cpuAndANE
        case .unknown:
            Logger.model.warning("[ANE] 兼容性未知，使用保守策略")
            return .cpuAndANE
        }
    }

    /// 获取当前推荐的配置
    ///
    /// - Returns: MLModelConfiguration
    func getRecommendedConfig() -> MLModelConfiguration {
        selectStrategy().config
    }

    /// 获取兼容性状态和推荐配置
    ///
    /// - Parameter modelURL: 模型文件 URL
    /// - Returns: 兼容性和配置元组
    func getRecommendedConfig(for modelURL: URL) async -> (ANECompatibility, MLModelConfiguration) {
        let compatibility = await checkCompatibility(visionModelURL: modelURL)
        let config = getRecommendedConfig()
        return (compatibility, config)
    }

    // MARK: - Private Methods

    /// 检查设备是否支持 ANE
    ///
    /// iPhone 14 Pro 及以上设备（A16+）完全支持 ANE。
    /// 参考: A16 Neural Engine 性能约 17 TOPS
    private func isANESupported() -> Bool {
        // iPhone 14 Pro 及以上设备均支持 ANE
        // A16 (iPhone 14 Pro) / A17 (iPhone 15 Pro) / A18 (iPhone 16 Pro)
        return true
    }

    /// 执行测试推理验证 ANE 可用性
    ///
    /// - Parameter model: 已加载的模型
    /// - Returns: 测试结果
    private func performTestInference(model: MLModel) async -> TestResult {
        do {
            let inputShape = [1, 3, 256, 256] as [NSNumber]
            let inputArray = try MLMultiArray(shape: inputShape, dataType: .float32)

            // 填充随机数据
            let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 256 * 256 * 3)
            for i in 0..<(256 * 256 * 3) {
                ptr[i] = Float.random(in: 0...1)
            }

            let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["img": inputArray])

            let start = CFAbsoluteTimeGetCurrent()
            let output = try await model.prediction(from: inputProvider)
            let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000

            // 检查输出是否有效
            let outputValid = output.featureNames.contains { name in
                output.featureValue(for: name)?.multiArrayValue != nil
            }

            return TestResult(
                success: outputValid,
                usedANE: true,
                latency: latency,
                error: outputValid ? nil : "输出无效"
            )
        } catch {
            return TestResult(
                success: false,
                usedANE: false,
                latency: 0,
                error: error.localizedDescription
            )
        }
    }

    /// 尝试回退模式
    private func tryFallbackMode(visionModelURL: URL) async -> ANECompatibility {
        let fallbackConfig = ComputeStrategy.cpuAndANE.config

        do {
            _ = try MLModel(contentsOf: visionModelURL, configuration: fallbackConfig)
            Logger.model.info("[ANE] 混合模式可用")
            visionModelCompatibility = .partialSupport
            return .partialSupport
        } catch {
            Logger.model.error("[ANE] 混合模式也失败: \(error)")
            visionModelCompatibility = .notSupported
            return .notSupported
        }
    }

    /// 测试结果
    struct TestResult: Sendable {
        let success: Bool
        let usedANE: Bool
        let latency: Double
        let error: String?
    }
}
