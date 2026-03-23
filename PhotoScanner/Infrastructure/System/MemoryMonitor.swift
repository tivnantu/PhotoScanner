//
// MemoryMonitor.swift
// PhotoScanner
//
// 内存监控器
// 监听系统内存警告，通知注册的处理器释放内存。
//

import Foundation
import UIKit
import OSLog

/// 内存监控器
///
/// 监听系统内存警告，通知注册的处理器释放内存。
/// 使用 actor 保护状态，线程安全。
///
/// ## 使用示例
/// ```swift
/// let monitor = MemoryMonitor()
///
/// // 注册内存警告处理器
/// await monitor.register(name: "ThumbnailCache") {
///     await thumbnailCache.clearMemoryCache()
/// }
///
/// // 获取当前内存使用
/// let usageMB = await monitor.memoryUsageMB
/// ```
actor MemoryMonitor {

    // MARK: - Types

    /// 内存处理器签名
    typealias MemoryHandler = @Sendable () async -> Void

    // MARK: - Properties

    private var handlers: [String: MemoryHandler] = [:]
    private var observation: NSObjectProtocol?

    // MARK: - Initialization

    /// 创建内存监控器
    init() {
        setupObserver()
    }

    deinit {
        if let observation = observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    // MARK: - Public Methods

    /// 注册内存警告处理器
    /// - Parameters:
    ///   - name: 处理器名称（用于取消注册）
    ///   - handler: 内存警告处理器
    func register(name: String, handler: @escaping MemoryHandler) {
        handlers[name] = handler
        Logger.index.info("[内存] 已注册处理器: \(name)")
    }

    /// 取消注册内存警告处理器
    /// - Parameter name: 处理器名称
    func unregister(name: String) {
        handlers.removeValue(forKey: name)
        Logger.index.info("[内存] 已注销处理器: \(name)")
    }

    /// 处理内存警告
    ///
    /// 调用所有注册的处理器释放内存。
    func handleMemoryWarning() async {
        Logger.index.warning("[内存] 收到内存警告，开始释放...")

        for (name, handler) in handlers {
            await handler()
            Logger.index.info("[内存] 已执行处理器: \(name)")
        }

        let usage = memoryUsageMB
        Logger.index.info("[内存] 释放完成, 当前使用: \(usage)MB")
    }

    /// 获取当前内存使用量（MB）
    var memoryUsageMB: Int { Int(Self.currentMemoryMB()) }

    /// 获取当前 App 内存使用量（MB），供任意线程调用
    static func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    // MARK: - Private Methods

    private func setupObserver() {
        observation = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryWarning()
            }
        }
    }
}
