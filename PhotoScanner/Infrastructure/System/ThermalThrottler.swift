//
// ThermalThrottler.swift
// PhotoScanner
//
// 设备热管理节流器
// 监控设备温度，当过热时自动暂停推理，冷却后恢复。
//

import Foundation
import OSLog

/// 设备热管理节流器
///
/// 监控 `ProcessInfo.thermalState`，当设备过热时自动暂停批量推理操作，
/// 冷却后恢复执行。通过动态调整推理间隔来平衡速度和发热。
///
/// ## 使用方式
/// ```swift
/// let throttler = ThermalThrottler()
///
/// for item in workItems {
///     try await throttler.waitIfNeeded()  // 过热时阻塞，冷却后继续
///     await doWork(item)
///     await throttler.yieldBetweenInferences()  // 批间让步
/// }
/// ```
///
/// ## 温度状态
/// - nominal: 正常，全速运行
/// - fair: 轻微发热，推理间隔 50ms
/// - serious: 严重发热，暂停推理
/// - critical: 危急发热，暂停推理并延长恢复等待
actor ThermalThrottler {

    /// 节流状态
    enum ThrottleState: Equatable, Sendable {
        /// 正常运行
        case running
        /// 已暂停（过热），附带暂停时间
        case paused(since: Date)
    }

    // MARK: - Properties

    /// 当前节流状态
    private(set) var state: ThrottleState = .running

    /// 推理间隔（毫秒），根据温度动态调整
    private(set) var inferenceDelayMs: UInt64 = 0

    /// 热状态检查间隔（暂停期间轮询）
    private let pollIntervalSeconds: TimeInterval = 3.0

    /// 暂停回调（UI 更新用）
    private var onStateChanged: (@Sendable (ThrottleState) -> Void)?

    /// 统计：累计暂停时间
    private(set) var totalPausedDuration: TimeInterval = 0

    // MARK: - Init

    /// 创建热管理节流器
    /// - Parameter onStateChanged: 状态变更回调，在状态切换时调用
    init(onStateChanged: (@Sendable (ThrottleState) -> Void)? = nil) {
        self.onStateChanged = onStateChanged
    }

    // MARK: - Core API

    /// 在每次推理前调用：如果设备过热则阻塞等待冷却
    ///
    /// 检查当前温度状态：
    /// - 如果温度正常或轻微，继续执行
    /// - 如果温度严重或危急，暂停并轮询等待冷却
    ///
    /// - Throws: `CancellationError` 如果 Task 被取消
    func waitIfNeeded() async throws {
        try Task.checkCancellation()

        let thermal = ProcessInfo.processInfo.thermalState
        updateDelay(for: thermal)

        guard thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue else {
            // 温度正常或轻微，正常执行
            if case .paused(let since) = state {
                totalPausedDuration += Date().timeIntervalSince(since)
                state = .running
                onStateChanged?(.running)
                Logger.model.info("设备温度恢复，继续索引构建 (累计暂停 \(String(format: "%.0f", self.totalPausedDuration))s)")
            }
            return
        }

        // 温度严重或危急，暂停
        let pauseStartTime: Date
        if case .running = state {
            pauseStartTime = Date()
            state = .paused(since: pauseStartTime)
            onStateChanged?(state)
            Logger.model.warning("设备温度过高 (\(thermal.label))，暂停推理")
        } else if case .paused(let since) = state {
            pauseStartTime = since
        } else {
            pauseStartTime = Date()
        }

        // 轮询等待冷却（带超时保护）
        let maxPauseDuration: TimeInterval = 300 // 最大暂停 5 分钟
        while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            try Task.checkCancellation()

            // 检查是否超过最大暂停时间
            let currentPauseDuration = Date().timeIntervalSince(pauseStartTime)
            if currentPauseDuration > maxPauseDuration {
                totalPausedDuration += currentPauseDuration
                state = .running
                onStateChanged?(.running)
                Logger.model.warning("设备持续过热超过 \(Int(maxPauseDuration/60)) 分钟，强制恢复执行")
                // 恢复后使用更长的延迟来降低发热
                try await Task.sleep(for: .seconds(5))
                return
            }

            try await Task.sleep(for: .seconds(pollIntervalSeconds))
        }

        // 冷却恢复
        if case .paused(let since) = state {
            totalPausedDuration += Date().timeIntervalSince(since)
        }
        state = .running
        onStateChanged?(.running)
        Logger.model.info("设备温度恢复至 \(ProcessInfo.processInfo.thermalState.label)，恢复推理")

        // 恢复后先额外冷却一小段时间，避免快速反弹
        try await Task.sleep(for: .seconds(1))
    }

    /// 在每次推理后调用：让出 CPU + 动态延迟
    ///
    /// 根据温度状态调整延迟：
    /// - nominal: 0ms（全速）
    /// - fair: 50ms
    /// - serious/critical: 由 waitIfNeeded 阻塞
    func yieldBetweenInferences() async {
        await Task.yield()

        if inferenceDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(inferenceDelayMs))
        }
    }

    // MARK: - Private

    /// 根据温度动态调整推理间隔
    private func updateDelay(for thermal: ProcessInfo.ThermalState) {
        switch thermal {
        case .nominal:
            inferenceDelayMs = 0
        case .fair:
            inferenceDelayMs = 50
        case .serious:
            inferenceDelayMs = 200
        case .critical:
            inferenceDelayMs = 500
        @unknown default:
            inferenceDelayMs = 100
        }
    }
}

// MARK: - ProcessInfo.ThermalState Extension

extension ProcessInfo.ThermalState {

    /// 可读标签
    nonisolated var label: String {
        switch self {
        case .nominal:  "正常"
        case .fair:     "轻微"
        case .serious:  "严重"
        case .critical: "危急"
        @unknown default: "未知"
        }
    }
}
