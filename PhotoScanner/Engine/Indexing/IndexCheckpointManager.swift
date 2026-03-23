import Foundation
import OSLog

// MARK: - IndexCheckpointManager

/// 索引检查点管理器
///
/// 负责检查点的生命周期管理，包括：
/// - 内存缓存：避免频繁磁盘读取
/// - 进度记录：便捷方法更新进度
/// - 完成清理：标记完成后删除检查点
/// - 版本兼容：支持向后兼容的迁移
///
/// ## 设计背景
/// 索引构建可能耗时较长（数千张图片），需要支持断点续传。
/// 检查点记录当前进度和候选资源 ID，以便崩溃后恢复。
///
/// ## 使用示例
/// ```swift
/// // 开始构建
/// let checkpoint = await manager.createCheckpoint(
///     candidateAssetIdentifiers: assetIds,
///     totalCount: assets.count
/// )
///
/// // 记录进度
/// await manager.recordProgress(
///     completedCount: processedCount,
///     totalCount: total
/// )
///
/// // 定期保存
/// await manager.saveCheckpoint(to: store)
///
/// // 完成后清理
/// await manager.markCompleted(store: store)
/// ```
actor IndexCheckpointManager: Sendable {

    // MARK: - 属性

    /// 当前检查点（内存缓存）
    private var currentCheckpoint: IndexCheckpoint?

    /// 检查点版本号（用于兼容性校验）
    private let currentVersion = 1

    // MARK: - 初始化

    init() {}

    // MARK: - 公开方法

    /// 创建新检查点
    ///
    /// - Parameters:
    ///   - candidateAssetIdentifiers: 候选资源 ID 列表
    ///   - totalCount: 总图片数
    /// - Returns: 新创建的检查点
    func createCheckpoint(
        candidateAssetIdentifiers: [String],
        totalCount: Int
    ) -> IndexCheckpoint {
        let checkpoint = IndexCheckpoint.building(
            candidateAssetIdentifiers: candidateAssetIdentifiers,
            completedCount: 0,
            totalCount: totalCount
        )
        currentCheckpoint = checkpoint
        Logger.index.debug("检查点已创建: totalCount=\(totalCount)")
        return checkpoint
    }

    /// 从存储加载检查点
    ///
    /// - Parameter store: 索引存储
    /// - Returns: 加载的检查点，不存在或版本不兼容返回 nil
    func loadCheckpoint(from store: any IndexStore) async -> IndexCheckpoint? {
        // 优先使用内存缓存
        if let cached = currentCheckpoint {
            Logger.index.debug("检查点命中内存缓存")
            return cached
        }

        do {
            guard let checkpoint = try await store.loadCheckpoint() else {
                Logger.index.debug("检查点不存在")
                return nil
            }

            // 验证版本兼容性（当前只有 v1，未来可扩展）
            guard checkpoint.stage != .idle else {
                Logger.index.debug("检查点状态为 idle，忽略")
                return nil
            }

            currentCheckpoint = checkpoint
            Logger.index.info("检查点已加载: stage=\(checkpoint.stage.rawValue), progress=\(checkpoint.completedCount)/\(checkpoint.totalCount)")
            return checkpoint
        } catch {
            Logger.index.warning("检查点加载失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 记录进度（仅更新内存中的检查点）
    ///
    /// - Parameters:
    ///   - completedCount: 已完成数量
    ///   - totalCount: 总数量
    func recordProgress(completedCount: Int, totalCount: Int) {
        guard var checkpoint = currentCheckpoint else {
            Logger.index.warning("记录进度失败: 检查点不存在")
            return
        }

        // 参数校验
        let normalizedCompleted = max(0, completedCount)
        let normalizedTotal = max(normalizedCompleted, totalCount)

        // 更新检查点
        checkpoint = IndexCheckpoint.building(
            candidateAssetIdentifiers: checkpoint.candidateAssetIdentifiers,
            completedCount: normalizedCompleted,
            totalCount: normalizedTotal
        )
        currentCheckpoint = checkpoint

        // 每处理 100 张记录一次日志
        if normalizedCompleted % 100 == 0 || normalizedCompleted == normalizedTotal {
            Logger.index.debug("索引进度: \(normalizedCompleted)/\(normalizedTotal)")
        }
    }

    /// 标记失败
    ///
    /// - Parameters:
    ///   - message: 失败信息
    func markFailed(message: String) {
        guard let checkpoint = currentCheckpoint else { return }

        currentCheckpoint = IndexCheckpoint.failed(
            candidateAssetIdentifiers: checkpoint.candidateAssetIdentifiers,
            completedCount: checkpoint.completedCount,
            totalCount: checkpoint.totalCount,
            message: message
        )

        Logger.index.error("索引失败: \(message)")
    }

    /// 保存检查点到存储
    ///
    /// - Parameter store: 索引存储
    func saveCheckpoint(to store: any IndexStore) async {
        guard let checkpoint = currentCheckpoint else {
            Logger.index.debug("检查点为空，跳过保存")
            return
        }

        do {
            try await store.saveCheckpoint(checkpoint)
            Logger.index.debug("检查点已保存: stage=\(checkpoint.stage.rawValue)")
        } catch {
            Logger.index.warning("检查点保存失败: \(error.localizedDescription)")
        }
    }

    /// 标记完成（清理检查点）
    ///
    /// - Parameter store: 索引存储
    func markCompleted(store: any IndexStore) async {
        currentCheckpoint = nil

        // 保存一个 idle 状态的检查点，表示索引已就绪
        let completedCheckpoint = IndexCheckpoint(
            stage: .ready,
            candidateAssetIdentifiers: [],
            completedCount: 0,
            totalCount: 0,
            message: nil,
            updatedAt: Date()
        )

        do {
            try await store.saveCheckpoint(completedCheckpoint)
            Logger.index.info("索引构建完成，检查点已清理")
        } catch {
            Logger.index.warning("清理检查点失败: \(error.localizedDescription)")
        }
    }

    /// 获取当前检查点（只读）
    var checkpoint: IndexCheckpoint? {
        currentCheckpoint
    }

    /// 是否有进行中的检查点
    var hasActiveCheckpoint: Bool {
        guard let checkpoint = currentCheckpoint else { return false }
        return checkpoint.stage == .building
    }
}


