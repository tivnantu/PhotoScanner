import Foundation
import OSLog
import Accelerate

actor MMapBruteForceVectorStore: VectorStore {
    private let indexStore: DiskBackedIndexStore

    private var manifest: IndexManifest?
    private var rows: [BinaryIndexRowMetadata] = []
    private var mappedData: Data?
    private var dataOffset: Int = 0

    init(indexStore: DiskBackedIndexStore) {
        self.indexStore = indexStore
    }

    func restoreIfAvailable() async throws -> Bool {
        guard let manifest = try await indexStore.loadManifest() else {
            self.manifest = nil
            self.rows = []
            self.mappedData = nil
            self.dataOffset = 0
            return false
        }

        let vectorURL = await indexStore.vectorFileURL()
        guard FileManager.default.fileExists(atPath: vectorURL.path) else {
            throw PSError.storageCorrupted("manifest 已存在，但缺少向量主文件")
        }

        let data: Data
        do {
            data = try Data(contentsOf: vectorURL, options: .mappedIfSafe)
        } catch {
            throw PSError.resourceUnreadable(path: vectorURL.path, reason: error.localizedDescription)
        }

        let parsed = try IndexBinaryFormat.parse(data)
        guard parsed.embeddingDimension == manifest.embeddingDimension else {
            throw PSError.storageCorrupted(
                "向量主文件维度与 manifest 不一致：\(parsed.embeddingDimension) != \(manifest.embeddingDimension)"
            )
        }
        guard parsed.itemCount == manifest.itemCount else {
            throw PSError.storageCorrupted(
                "向量主文件条目数与 manifest 不一致：\(parsed.itemCount) != \(manifest.itemCount)"
            )
        }

        self.manifest = manifest
        self.rows = parsed.rows
        self.mappedData = data
        self.dataOffset = parsed.dataOffset

        Logger.index.info("mmap 向量主文件已加载，条目数: \(manifest.itemCount)")
        return true
    }

    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws {
        try await indexStore.saveSnapshot(snapshot)
        _ = try await restoreIfAvailable()
        Logger.index.info("mmap VectorStore 已替换快照，条目数: \(snapshot.manifest.itemCount)")
    }

    func loadSnapshot() async throws -> IndexSnapshot? {
        try await indexStore.loadSnapshot()
    }

    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult] {
        guard !queryEmbedding.isEmpty else {
            throw PSError.invalidInput("queryEmbedding 不能为空")
        }
        guard queryEmbedding.allSatisfy(\.isFinite) else {
            throw PSError.invalidModelOutput("queryEmbedding 包含非有限数值")
        }
        guard topK > 0 else {
            throw PSError.invalidInput("topK 必须大于 0")
        }

        if mappedData == nil {
            _ = try await restoreIfAvailable()
        }

        guard let manifest else {
            throw PSError.serviceNotReady(service: "VectorStore", reason: "索引尚未建立")
        }
        guard let mappedData else {
            throw PSError.serviceNotReady(service: "VectorStore", reason: "向量主文件尚未加载")
        }
        guard queryEmbedding.count == manifest.embeddingDimension else {
            throw PSError.invalidModelOutput(
                "查询向量维度不匹配，期望 \(manifest.embeddingDimension)，实际 \(queryEmbedding.count)"
            )
        }

        let rowCount = self.rows.count
        let limitedTopK = min(topK, rowCount)
        guard limitedTopK > 0 else {
            Logger.index.info("mmap VectorStore 检索完成，但当前索引为空")
            return []
        }

        let dimension = manifest.embeddingDimension
        let vectorOffset = self.dataOffset
        var topCandidates: [(row: Int, score: Float)] = []
        topCandidates.reserveCapacity(limitedTopK)

        func insertCandidate(row: Int, score: Float) {
            if topCandidates.count < limitedTopK {
                topCandidates.append((row: row, score: score))
                topCandidates.sort { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.row < rhs.row
                    }
                    return lhs.score > rhs.score
                }
                return
            }

            guard let weakest = topCandidates.last else {
                topCandidates = [(row: row, score: score)]
                return
            }
            guard score > weakest.score else {
                return
            }

            topCandidates.removeLast()
            topCandidates.append((row: row, score: score))
            topCandidates.sort { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.row < rhs.row
                }
                return lhs.score > rhs.score
            }
        }

        let startedAt = ContinuousClock.now

        try queryEmbedding.withUnsafeBufferPointer { queryBuffer in
            guard let queryBase = queryBuffer.baseAddress else {
                throw PSError.invalidInput("queryEmbedding 不能为空")
            }

            try mappedData.withUnsafeBytes { rawBuffer in
                guard let rawBase = rawBuffer.baseAddress else {
                    throw PSError.storageCorrupted("mmap 数据缓冲区为空")
                }

                let floatBase = rawBase
                    .advanced(by: vectorOffset)
                    .assumingMemoryBound(to: Float.self)

                for rowIndex in 0..<rowCount {
                    var score: Float = 0
                    vDSP_dotpr(
                        queryBase,
                        1,
                        floatBase.advanced(by: rowIndex * dimension),
                        1,
                        &score,
                        vDSP_Length(dimension)
                    )
                    insertCandidate(row: rowIndex, score: score)
                }
            }
        }

        let duration = startedAt.duration(to: .now)
        let results = topCandidates.map { candidate in
            let row = self.rows[candidate.row]
            return VectorSearchResult(
                assetLocalIdentifier: row.assetLocalIdentifier,
                assetFingerprint: row.assetFingerprint,
                score: candidate.score
            )
        }

        Logger.index.info(
            "mmap VectorStore 检索完成，候选数: \(rowCount)，返回数: \(results.count)，耗时: \(duration.components.seconds)s"
        )
        return results
    }

    func clear() async throws {
        try await indexStore.clear()
        manifest = nil
        rows = []
        mappedData = nil
        dataOffset = 0
        Logger.index.info("mmap VectorStore 已清空")
    }
}
