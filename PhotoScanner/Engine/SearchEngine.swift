import Foundation
import OSLog

final class SearchEngine: Sendable {
    private let embeddingService: EmbeddingService
    private let vectorStore: any VectorStore

    init(embeddingService: EmbeddingService, vectorStore: any VectorStore) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
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

        let startedAt = ContinuousClock.now
        let queryEmbedding = try await embeddingService.embedText(sanitizedText)
        let results = try await vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
        let duration = startedAt.duration(to: .now)

        Logger.search.info(
            "文搜图完成，文本长度: \(sanitizedText.count)，返回结果: \(results.count)，耗时: \(duration.components.seconds)s"
        )
        return results
    }
}
