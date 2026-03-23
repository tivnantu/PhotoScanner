import Foundation
import OSLog

actor IndexEngine {
    private let embeddingService: EmbeddingService
    private let indexStore: DiskBackedIndexStore
    private let vectorStore: MMapBruteForceVectorStore

    init(
        embeddingService: EmbeddingService,
        indexStore: DiskBackedIndexStore,
        vectorStore: MMapBruteForceVectorStore
    ) {
        self.embeddingService = embeddingService
        self.indexStore = indexStore
        self.vectorStore = vectorStore
    }

    func loadCurrentState() async -> IndexBuildState {
        do {
            if let checkpoint = try await indexStore.loadCheckpoint() {
                switch checkpoint.stage {
                case .building:
                    if let progress = checkpoint.progress {
                        return .building(progress: progress)
                    }
                    return .preparing
                case .failed:
                    return .failed(message: checkpoint.message ?? "索引构建失败")
                case .idle, .ready:
                    break
                }
            }

            if let manifest = try await indexStore.loadManifest() {
                _ = try await vectorStore.restoreIfAvailable()
                return .ready(manifest: manifest)
            }

            return .idle
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func loadImportedAssets() async throws -> [StoredIndexedAsset] {
        try await indexStore.loadImportedAssets()
    }

    func loadImageData(for assetLocalIdentifier: String) async throws -> Data? {
        try await indexStore.importedAssetData(for: assetLocalIdentifier)
    }

    func addAssetsAndRebuild(
        _ inputs: [IndexedAssetInput],
        progressHandler: (@Sendable (IndexBuildState) async -> Void)? = nil
    ) async throws -> IndexBuildState {
        _ = try await indexStore.saveImportedAssets(inputs)
        let allAssets = try await indexStore.loadImportedAssets()
        return try await buildIndex(
            from: allAssets,
            reuseExistingChunks: false,
            progressHandler: progressHandler
        )
    }

    func resumeBuildIfNeeded(
        progressHandler: (@Sendable (IndexBuildState) async -> Void)? = nil
    ) async throws -> IndexBuildState {
        guard let checkpoint = try await indexStore.loadCheckpoint(), checkpoint.stage == .building else {
            return await loadCurrentState()
        }

        let storedAssets = try await indexStore.loadImportedAssets()
        let candidateSet = Set(checkpoint.candidateAssetIdentifiers)
        let candidates = candidateSet.isEmpty
            ? storedAssets
            : storedAssets.filter { candidateSet.contains($0.assetLocalIdentifier) }

        guard !candidates.isEmpty else {
            try await indexStore.clearTransientBuildArtifacts()
            return .idle
        }

        return try await buildIndex(
            from: candidates,
            reuseExistingChunks: true,
            progressHandler: progressHandler
        )
    }

    func clearAll() async throws {
        try await vectorStore.clear()
    }

    private func buildIndex(
        from assets: [StoredIndexedAsset],
        reuseExistingChunks: Bool,
        progressHandler: (@Sendable (IndexBuildState) async -> Void)?
    ) async throws -> IndexBuildState {
        let sortedAssets = assets.sorted { $0.assetLocalIdentifier < $1.assetLocalIdentifier }
        guard !sortedAssets.isEmpty else {
            throw PSError.invalidInput("当前没有可索引的图片，请先选择图片")
        }

        try await embeddingService.initialize()
        await progressHandler?(.preparing)

        if !reuseExistingChunks {
            try await indexStore.clearTransientBuildArtifacts()
        }

        let descriptor = await embeddingService.modelDescriptor
        let baseManifest = try IndexManifest(
            modelDescriptor: descriptor,
            modelFingerprint: Self.modelFingerprint(for: descriptor),
            resourceFingerprint: try BundleResource.resourceFingerprint(),
            createdAt: Date(),
            updatedAt: Date(),
            itemCount: 0
        )

        let existingEntries = reuseExistingChunks ? try await indexStore.loadChunkEntries() : []
        var entriesByID = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.assetLocalIdentifier, $0) })
        var completedCount = entriesByID.count

        try await indexStore.saveCheckpoint(
            .building(
                candidateAssetIdentifiers: sortedAssets.map(\.assetLocalIdentifier),
                completedCount: completedCount,
                totalCount: sortedAssets.count
            )
        )

        if let progress = try? IndexBuildProgress(completedCount: completedCount, totalCount: sortedAssets.count) {
            await progressHandler?(.building(progress: progress))
        }

        for asset in sortedAssets where entriesByID[asset.assetLocalIdentifier] == nil {
            guard let imageData = try await indexStore.importedAssetData(for: asset.assetLocalIdentifier) else {
                throw PSError.resourceUnreadable(
                    path: asset.assetLocalIdentifier,
                    reason: "导入图片 sidecar 缺失"
                )
            }

            let embedding = try await embeddingService.embedImage(imageData)
            let entry = try IndexEntry(
                assetLocalIdentifier: asset.assetLocalIdentifier,
                assetFingerprint: asset.assetFingerprint,
                embedding: embedding,
                createdAt: asset.createdAt,
                updatedAt: asset.updatedAt
            )
            try await indexStore.saveChunk(entry)
            entriesByID[entry.assetLocalIdentifier] = entry
            completedCount += 1

            let checkpoint = IndexCheckpoint.building(
                candidateAssetIdentifiers: sortedAssets.map(\.assetLocalIdentifier),
                completedCount: completedCount,
                totalCount: sortedAssets.count
            )
            try await indexStore.saveCheckpoint(checkpoint)

            if let progress = checkpoint.progress {
                await progressHandler?(.building(progress: progress))
            }
        }

        let finalEntries = sortedAssets.compactMap { entriesByID[$0.assetLocalIdentifier] }
        guard finalEntries.count == sortedAssets.count else {
            throw PSError.storageCorrupted("构建完成后索引条目数不完整")
        }

        let manifest = try baseManifest.withItemCount(finalEntries.count)
        let snapshot = try IndexSnapshot(manifest: manifest, entries: finalEntries)
        try await vectorStore.replaceSnapshot(snapshot)

        let readyState = IndexBuildState.ready(manifest: manifest)
        await progressHandler?(readyState)
        Logger.index.info("索引构建完成，条目数: \(manifest.itemCount)")
        return readyState
    }

    private static func modelFingerprint(for descriptor: ModelDescriptor) -> String {
        [
            descriptor.id,
            descriptor.version,
            String(descriptor.embeddingDimension),
            String(descriptor.imageSize),
            String(descriptor.contextLength)
        ].joined(separator: "|")
    }
}
