//
// Errors.swift
// PhotoScanner
//
// 统一错误类型。
// 每个 case 对应一种可识别的失败场景，上层按需 switch 处理。
//

import Foundation

/// PhotoScanner 全局错误枚举
enum PSError: Error, Equatable {

    // MARK: - 模型

    /// 模型文件未找到（附带期望路径）
    case modelNotFound(String)

    /// 模型加载失败（附带底层原因）
    case modelLoadFailed(String)

    /// 推理过程出错（附带底层原因）
    case inferenceFailed(String)

    // MARK: - 输入

    /// 无效输入（附带说明）
    case invalidInput(String)

    // MARK: - 资源

    /// Bundle 中找不到指定资源
    case resourceNotFound(name: String, extension: String)

    // MARK: - 通用

    /// 未知错误（附带说明）
    case unknown(String)
}

// MARK: - 用户可读描述

extension PSError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "模型文件未找到: \(path)"
        case .modelLoadFailed(let reason):
            return "模型加载失败: \(reason)"
        case .inferenceFailed(let reason):
            return "推理失败: \(reason)"
        case .invalidInput(let detail):
            return "无效输入: \(detail)"
        case .resourceNotFound(let name, let ext):
            return "资源未找到: \(name).\(ext)"
        case .unknown(let detail):
            return "未知错误: \(detail)"
        }
    }
}
