import Foundation
import OSLog

actor IndexEngine {
    private let embeddingService: EmbeddingService
    private let indexStore: DiskBackedIndexStore
    private let vectorStore: MMapBruteForceVectorStore
    private let photoLibraryAssetProvider: PhotoLibraryAssetProvider
    private let performanceStore: RuntimePerformanceStore
    
    /// 热管理节流器：防止设备过热
    private let thermalThrottler = ThermalThrottler()

    init(
        embeddingService: EmbeddingService,
        indexStore: DiskBackedIndexStore,
        vectorStore: MMapBruteForceVectorStore,
        photoLibraryAssetProvider: PhotoLibraryAssetProvider,
        performanceStore: RuntimePerformanceStore
    ) {
        self.embeddingService = embeddingService
        self.indexStore = indexStore
        self.vectorStore = vectorStore
        self.photoLibraryAssetProvider = photoLibraryAssetProvider
        self.performanceStore = performanceStore
    }

    func loadCurrentState() async -> IndexBuildState {
        let startedAt = ContinuousClock.now

        do {
            let state: IndexBuildState

            if let checkpoint = try await indexStore.loadCheckpoint() {
                switch checkpoint.stage {
                case .building:
                    if let progress = checkpoint.progress {
                        state = .building(progress: progress)
                    } else {
                        state = .preparing
                    }
                case .failed:
                    state = .failed(message: checkpoint.message ?? "索引构建失败")
                case .idle, .ready:
                    if let manifest = try await indexStore.loadManifest() {
                        _ = try await vectorStore.restoreIfAvailable()
                        state = .ready(manifest: manifest)
                    } else {
                        state = .idle
                    }
                }
            } else if let manifest = try await indexStore.loadManifest() {
                _ = try await vectorStore.restoreIfAvailable()
                state = .ready(manifest: manifest)
            } else {
                state = .idle
            }

            await performanceStore.record(
                .stateRestore,
                duration: startedAt.duration(to: .now),
                detail: Self.restoreDetail(for: state)
            )
            return state
        } catch {
            let failureMessage = error.localizedDescription
            await performanceStore.record(
                .stateRestore,
                duration: startedAt.duration(to: .now),
                detail: "恢复失败：\(failureMessage)"
            )
            return .failed(message: failureMessage)
        }
    }

    func loadImportedAssets() async throws -> [StoredIndexedAsset] {
        try await indexStore.loadImportedAssets()
    }

    func addAssetsAndRebuild(
        _ inputs: [IndexedAssetInput],
        progressHandler: (@Sendable (IndexBuildState) async -> Void)? = nil
    ) async throws -> IndexBuildState {
        _ = try await indexStore.saveImportedAssets(inputs)
        let allAssets = try await indexStore.loadImportedAssets()
        let photoLibraryBackedCount = allAssets.filter(\.isPhotoLibraryBacked).count
        Logger.index.info(
            "准备重建索引，本次输入 \(inputs.count) 张，累计 \(allAssets.count) 张，系统相册绑定 \(photoLibraryBackedCount) 张"
        )
        return try await buildIndex(
            from: allAssets,
            reuseExistingChunks: false,
            progressHandler: progressHandler
        )
    }

    func rebuildImportedAssets(
        progressHandler: (@Sendable (IndexBuildState) async -> Void)? = nil
    ) async throws -> IndexBuildState {
        let storedAssets = try await indexStore.loadImportedAssets()
        return try await buildIndex(
            from: storedAssets,
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
        let startedAt = ContinuousClock.now
        let sortedAssets = assets.sorted { $0.assetLocalIdentifier < $1.assetLocalIdentifier }
        guard !sortedAssets.isEmpty else {
            throw PSError.invalidInput("当前没有可索引的图片，请先选择图片")
        }

        let candidateAssetIdentifiers = sortedAssets.map(\.assetLocalIdentifier)
        let totalCount = sortedAssets.count
        var completedCount = 0
        
        // 错误恢复策略
        var consecutiveFailures = 0
        var skippedCount = 0
        let maxConsecutiveFailures = 10

        do {
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
            completedCount = entriesByID.count

            try await indexStore.saveCheckpoint(
                .building(
                    candidateAssetIdentifiers: candidateAssetIdentifiers,
                    completedCount: completedCount,
                    totalCount: totalCount
                )
            )

            if let progress = try? IndexBuildProgress(completedCount: completedCount, totalCount: totalCount) {
                await progressHandler?(.building(progress: progress))
            }

            for asset in sortedAssets where entriesByID[asset.assetLocalIdentifier] == nil {
                // 热节流：过热时暂停，冷却后恢复
                try await thermalThrottler.waitIfNeeded()
                
                // 错误恢复：单张失败跳过，连续失败计数
                do {
                    let imageData = try await resolveImageData(for: asset)
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
                    
                    // 成功后重置连续失败计数
                    consecutiveFailures = 0

                    let checkpoint = IndexCheckpoint.building(
                        candidateAssetIdentifiers: candidateAssetIdentifiers,
                        completedCount: completedCount,
                        totalCount: totalCount
                    )
                    try await indexStore.saveCheckpoint(checkpoint)

                    if let progress = checkpoint.progress {
                        await progressHandler?(.building(progress: progress))
                    }
                } catch {
                    // 单张失败跳过，记录日志
                    consecutiveFailures += 1
                    skippedCount += 1
                    Logger.index.warning(
                        "索引构建跳过失败图片: \(Self.shortIdentifier(asset.assetLocalIdentifier)), 原因: \(error.localizedDescription), 连续失败: \(consecutiveFailures)"
                    )
                    
                    // 连续失败 10 次中止
                    if consecutiveFailures >= maxConsecutiveFailures {
                        throw PSError.storageCorrupted("连续失败 \(maxConsecutiveFailures) 次，中止索引构建")
                    }
                    // 单张失败继续处理下一张
                }
                
                // 推理后让出 CPU，避免持续高负载
                await thermalThrottler.yieldBetweenInferences()
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

            let buildDuration = startedAt.duration(to: .now)
            await performanceStore.record(
                .indexBuild,
                duration: buildDuration,
                detail: "候选 \(totalCount) 张，完成 \(manifest.itemCount) 张，续建 \(reuseExistingChunks ? "是" : "否")"
            )
            Logger.index.info("索引构建完成，条目数: \(manifest.itemCount)")
            return readyState
        } catch {
            let failureMessage = Self.checkpointFailureMessage(for: error)
            let failedCheckpoint = IndexCheckpoint.failed(
                candidateAssetIdentifiers: candidateAssetIdentifiers,
                completedCount: completedCount,
                totalCount: totalCount,
                message: failureMessage
            )
            try? await indexStore.saveCheckpoint(failedCheckpoint)
            await progressHandler?(.failed(message: failureMessage))
            await performanceStore.record(
                .indexBuild,
                duration: startedAt.duration(to: .now),
                detail: "候选 \(totalCount) 张，失败于 \(completedCount)/\(totalCount)"
            )
            Logger.index.error("索引构建失败: \(failureMessage)")
            throw error
        }
    }

    private func resolveImageData(for asset: StoredIndexedAsset) async throws -> Data {
        // 所有图片必须通过系统相册获取
        guard let photoLibraryAssetIdentifier = asset.photoLibraryAssetIdentifier else {
            throw PSError.resourceUnreadable(
                path: asset.assetLocalIdentifier,
                reason: "图片没有系统相册标识，无法从相册获取"
            )
        }
        
        guard let imageData = await photoLibraryAssetProvider.originalImageData(for: photoLibraryAssetIdentifier) else {
            let accessState = await photoLibraryAssetProvider.currentAccessState()
            let reason: String
            if accessState.hasReadAccess {
                reason = "系统相册资源已失效"
            } else {
                reason = "系统相册当前不可访问"
            }
            Logger.index.error(
                "构建取图失败: \(Self.shortIdentifier(asset.assetLocalIdentifier))，photoIdentifier: \(Self.shortIdentifier(photoLibraryAssetIdentifier))，原因: \(reason)"
            )
            throw PSError.resourceUnreadable(path: photoLibraryAssetIdentifier, reason: reason)
        }
        
        Logger.index.debug(
            "构建取图: \(Self.shortIdentifier(asset.assetLocalIdentifier)) 从系统相册获取原图，photoIdentifier: \(Self.shortIdentifier(photoLibraryAssetIdentifier))"
        )
        return imageData
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

    private static func restoreDetail(for state: IndexBuildState) -> String {
        switch state {
        case .idle:
            return "当前无可恢复索引"
        case .preparing:
            return "恢复到 preparing 状态"
        case .building(let progress):
            return "恢复到 building：\(progress.completedCount)/\(progress.totalCount)"
        case .ready(let manifest):
            return "恢复到 ready：\(manifest.itemCount) 张"
        case .failed(let message):
            return "恢复到 failed：\(message)"
        }
    }

    private static func checkpointFailureMessage(for error: Error) -> String {
        error.localizedDescription
    }

    private static func shortIdentifier(_ identifier: String) -> String {
        String(identifier.prefix(24))
    }
}
