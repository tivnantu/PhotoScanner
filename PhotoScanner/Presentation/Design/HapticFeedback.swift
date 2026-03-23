import UIKit

// MARK: - HapticFeedback

/// 触感反馈工具
///
/// 轻量封装系统反馈，便于在关键节点调用并复用分数语义。
///
/// ## 设计背景
/// iOS 系统提供的 UIFeedbackGenerator 需要选择合适的类型和时机。
/// 封装后提供语义化接口，避免每次都查阅文档。
///
/// ## 使用示例
/// ```swift
/// // 操作成功
/// HapticFeedback.success()
///
/// // 切换选择
/// HapticFeedback.selection()
///
/// // 根据分数自动选择
/// HapticFeedback.forScore(0.85)  // 成功
/// HapticFeedback.forScore(0.35)  // 错误
/// ```
enum HapticFeedback {

    // MARK: - 通知反馈
    
    /// 成功反馈（通知）
    /// - Note: 用于操作完成、保存成功等正向结果
    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 警告反馈（通知）
    /// - Note: 用于需要用户注意但不阻断的情况
    @MainActor
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 错误反馈（通知）
    /// - Note: 用于操作失败、验证错误等负向结果
    @MainActor
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - 选择反馈
    
    /// 选择变化（轻触）
    /// - Note: 用于 tab 切换、选项选择等
    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - 冲击反馈
    
    /// 轻量敲击
    /// - Parameter style: 冲击强度，默认 medium
    /// - Note: 用于按钮点击、轻微交互反馈
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - 语义化反馈
    
    /// 根据相似度分数触发语义化反馈
    ///
    /// 分数区间与反馈映射：
    /// - 0.7+ → 成功（找到相似图片）
    /// - 0.4~0.7 → 警告（部分匹配）
    /// - <0.4 → 错误（无匹配）
    ///
    /// - Parameter score: 相似度分数 [0, 1]
    @MainActor
    static func forScore(_ score: Double) {
        switch score {
        case 0.7...:
            success()
        case 0.4...:
            warning()
        default:
            error()
        }
    }
}
