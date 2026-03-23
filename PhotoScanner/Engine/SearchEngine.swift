import Foundation
import OSLog

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
