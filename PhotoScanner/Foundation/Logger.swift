//
// Logger.swift
// PhotoScanner
//
// 基于 OSLog 的日志门面。
// 按模块分类，便于 Console.app / Instruments 过滤。
//

import OSLog

extension Logger {

    private nonisolated(unsafe) static let subsystem = Bundle.main.bundleIdentifier ?? "cn.tivnantu.PhotoScanner"

    // MARK: - 模块分类

    /// 应用生命周期、启动、初始化
    nonisolated(unsafe) static let app = Logger(subsystem: subsystem, category: "App")

    /// 模型加载、推理、预处理
    nonisolated(unsafe) static let model = Logger(subsystem: subsystem, category: "Model")

    /// 搜索、相似度计算
    nonisolated(unsafe) static let search = Logger(subsystem: subsystem, category: "Search")

    /// 索引构建、维护
    nonisolated(unsafe) static let index = Logger(subsystem: subsystem, category: "Index")

    /// UI 交互、导航
    nonisolated(unsafe) static let ui = Logger(subsystem: subsystem, category: "UI")
}
