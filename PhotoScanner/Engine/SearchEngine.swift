import Foundation
import OSLog

// TODO: 并发模型 - SearchEngine 应为 actor 而非 Sendable class
// 问题：
// 1. 当前是 final class + Sendable，依赖 EmbeddingService（actor）需 await
// 2. 语义上更适合 actor，与 IndexEngine 保持一致
// 3. 为未来可变状态（如缓存、统计）预留隔离边界
// 影响：修改为 actor 后，调用方无需变更（已有 await）

final class SearchEngine: Sendable {
    private let embeddingService: EmbeddingService
    private let vectorStore: any VectorStore
    private let performanceStore: RuntimePerformanceStore

    init(
        embeddingService: EmbeddingService,
        vectorStore: any VectorStore,
        performanceStore: RuntimePerformanceStore
    ) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.performanceStore = performanceStore
    }

    func search(text: String, topK: Int = 12) async throws -> [VectorSearchResult] {
        let sanitizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedText.isEmpty else {
            throw PSError.invalidInput("搜索文本不能为空")
        }
        guard topK > 0 else {
            throw PSError.invalidInput("topK 必须大于 0")
        }

        try await embeddingService.initialize()

        let totalStartedAt = ContinuousClock.now

        do {
            let embeddingStartedAt = ContinuousClock.now
            let queryEmbedding = try await embeddingService.embedText(sanitizedText)
            let embeddingDuration = embeddingStartedAt.duration(to: .now)
            await performanceStore.record(
                .textEmbedding,
                duration: embeddingDuration,
                detail: "文本长度 \(sanitizedText.count)"
            )

            let vectorStartedAt = ContinuousClock.now
            let results = try await vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
            let vectorDuration = vectorStartedAt.duration(to: .now)
            await performanceStore.record(
                .vectorSearch,
                duration: vectorDuration,
                detail: "候选上限 \(topK)，返回 \(results.count) 条"
            )

            let totalDuration = totalStartedAt.duration(to: .now)
            await performanceStore.record(
                .searchTotal,
                duration: totalDuration,
                detail: "文本长度 \(sanitizedText.count)，结果 \(results.count) 条"
            )
            
            // TODO: 性能监控 - 添加 P95 ≤ 45ms 延迟预算告警
            // 问题：当前只记录性能指标，无主动告警/限制
            // 建议：
            // 1. 单次搜索超过 45ms 时记录 warning 日志
            // 2. 考虑添加超时控制 withTimeout(.milliseconds(45))
            // 3. 慢查询统计，用于识别性能退化

            Logger.search.info(
                "文搜图完成，文本长度: \(sanitizedText.count)，返回结果: \(results.count)，耗时: \(totalDuration.components.seconds)s"
            )
            return results
        } catch {
            let totalDuration = totalStartedAt.duration(to: .now)
            await performanceStore.record(
                .searchTotal,
                duration: totalDuration,
                detail: "文本长度 \(sanitizedText.count)，搜索失败"
            )
            Logger.search.error("文搜图失败: \(error.localizedDescription)")
            throw error
        }
    }
}
