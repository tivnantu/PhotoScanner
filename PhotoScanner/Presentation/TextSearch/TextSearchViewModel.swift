import Foundation
import Observation
import OSLog

struct TextSearchResultItem: Identifiable {
    let assetLocalIdentifier: String
    let displayTitle: String
    let sourceLabel: String
    let score: Float
    let previewData: Data?

    var id: String {
        assetLocalIdentifier
    }
}

enum TextImageFeedbackTone {
    case neutral
    case info
    case warning
    case error
}

struct TextImageFeedback {
    let systemImage: String
    let title: String
    let detail: String
    let tone: TextImageFeedbackTone
    let actionTitle: String?
}

private struct PhotoLibraryPreviewPayload {
    let displayTitle: String
    let sourceLabel: String
    let previewData: Data?
}

private extension PhotoLibraryAccessState {
    var metricsLabel: String {
        switch self {
        case .fullAccess:
            return "完全访问"
        case .limitedAccess:
            return "受限访问"
        case .notDetermined:
            return "未决定"
        case .unavailable:
            return "不可访问"
        }
    }
}

@Observable
@MainActor
final class TextSearchViewModel {
    var buildState: IndexBuildState = .idle
    var queryText: String = ""
    var isSearching = false
    var indexedAssets: [StoredIndexedAsset] = []
    var searchResults: [TextSearchResultItem] = []
    var searchFailure: TextImageFeedback?
    var hasAttemptedSearch = false
    var lastSubmittedQuery: String = ""
    var photoLibraryAccessState: PhotoLibraryAccessState = .notDetermined
    var performanceMetrics: [RuntimePerformanceMetric] = []

    var canSearch: Bool {
        !trimmedQuery.isEmpty
            && isIndexReady
            && !isSearching
            && !isBuilding
    }

    var isBuilding: Bool {
        if case .building = buildState {
            return true
        }
        return buildState == .preparing
    }

    var isIndexReady: Bool {
        if case .ready = buildState {
            return true
        }
        return false
    }

    var indexedCount: Int {
        indexedAssets.count
    }

    var photoLibraryBackedCount: Int {
        indexedAssets.filter(\.isPhotoLibraryBacked).count
    }

    var canRebuildFromImportedAssets: Bool {
        indexedCount > 0 && !isBuilding && !isSearching
    }

    var statusSystemImage: String {
        switch buildState {
        case .idle:
            return indexedCount > 0 ? "tray.and.arrow.down" : "photo.badge.plus"
        case .preparing, .building:
            return "gearshape.2"
        case .ready:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTitle: String {
        switch buildState {
        case .idle:
            return indexedCount > 0 ? "图片已准备就绪" : "还没有图片"
        case .preparing:
            return "正在准备..."
        case .building(let progress):
            return "正在处理图片（\(progress.completedCount)/\(progress.totalCount)）"
        case .ready(let manifest):
            return "可以搜索 \(manifest.itemCount) 张图片"
        case .failed:
            return "处理遇到问题"
        }
    }

    var statusDetail: String {
        switch buildState {
        case .idle:
            if indexedCount > 0 {
                return "已导入 \(indexedCount) 张图片，可添加更多或直接建立索引后开始搜索。"
            }
            return "从相册选择图片，建立搜索索引后就能用文字查找图片了。"
        case .preparing:
            return "正在整理图片并准备建立索引..."
        case .building(let progress):
            return "正在分析 \(progress.completedCount) / \(progress.totalCount) 张图片的视觉特征。"
        case .ready:
            return "已建立 \(indexedCount) 张图片的搜索索引，输入描述即可查找。"
        case .failed(let message):
            return statusFailureDetail(from: message)
        }
    }

    var statusActionTitle: String? {
        guard canRebuildFromImportedAssets else { return nil }

        switch buildState {
        case .idle, .failed:
            return "使用已导入图片重新建索引"
        default:
            return nil
        }
    }

    var importSourceHintText: String {
        if indexedCount == 0 {
            return "建议选择 10~50 张有代表性的图片，索引建立后即可开始搜索。"
        }
        return "当前已导入 \(indexedCount) 张，可继续添加或用现有图片重建索引。"
    }

    var searchHintText: String {
        if isBuilding {
            return "正在建立索引，完成后即可搜索。"
        }
        if !isIndexReady {
            return indexedCount > 0
                ? "请先完成索引建立（\(indexedCount) 张图片待处理）。"
                : "请先选择图片并建立索引。"
        }
        if trimmedQuery.isEmpty {
            return "输入自然语言描述，如：海边日落、红色灯笼、雪山与湖泊。"
        }
        return "搜索将匹配 \(indexedCount) 张图片，结果按相似度排序。"
    }

    var searchButtonTitle: String {
        isSearching ? "搜索中..." : "开始搜索"
    }

    var performanceHintText: String {
        "以下为关键步骤的耗时统计，帮助了解系统运行状态。"
    }

    var resultsSummaryText: String? {
        guard !searchResults.isEmpty else { return nil }
        return "共找到 \(searchResults.count) 张结果，已按相似度从高到低排序。"
    }

    var resultsFeedback: TextImageFeedback? {
        if isSearching {
            return TextImageFeedback(
                systemImage: "magnifyingglass",
                title: "正在检索图片",
                detail: lastSubmittedQuery.isEmpty
                    ? "正在生成文本向量并扫描本地索引。"
                    : "正在根据“\(lastSubmittedQuery)”生成文本向量并扫描本地索引。",
                tone: .info,
                actionTitle: nil
            )
        }

        if let searchFailure {
            return searchFailure
        }

        if !isIndexReady {
            return TextImageFeedback(
                systemImage: indexedCount > 0 ? "tray.and.arrow.down" : "photo.badge.plus",
                title: indexedCount > 0 ? "索引还没准备好" : "还没有可搜索的图片",
                detail: indexedCount > 0
                    ? "请先完成索引构建，构建完成后再输入文本搜索。"
                    : "先导入几张图片建立本地索引，搜索结果才会出现。",
                tone: .warning,
                actionTitle: nil
            )
        }

        if !hasAttemptedSearch && searchResults.isEmpty {
            return TextImageFeedback(
                systemImage: "text.magnifyingglass",
                title: "输入一段描述开始搜索",
                detail: "例如：海边日落、红色灯笼、两只猫、雪山与湖泊。",
                tone: .neutral,
                actionTitle: nil
            )
        }

        if searchResults.isEmpty {
            let querySummary = lastSubmittedQuery.isEmpty ? "当前描述词" : "“\(lastSubmittedQuery)”"
            return TextImageFeedback(
                systemImage: "magnifyingglass",
                title: "没有找到更匹配的图片",
                detail: "\(querySummary) 暂时没有命中结果，试试换更具体的主体、颜色、场景或动作词。",
                tone: .warning,
                actionTitle: nil
            )
        }

        return nil
    }

    private let indexEngine: IndexEngine
    private let searchEngine: SearchEngine
    private let photoLibraryAssetProvider: PhotoLibraryAssetProvider
    private let performanceStore: RuntimePerformanceStore
    private var hasInitialized = false

    private var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(services: AppServices) {
        self.indexEngine = services.indexEngine
        self.searchEngine = services.searchEngine
        self.photoLibraryAssetProvider = services.photoLibraryAssetProvider
        self.performanceStore = services.runtimePerformanceStore
    }

    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        buildState = await indexEngine.loadCurrentState()
        do {
            try await refreshImportedAssets()
            if case .building = buildState {
                try await resumeInterruptedBuild()
            }
        } catch {
            applyIndexFailure(error)
            await refreshPerformanceMetrics()
            return
        }

        await refreshPerformanceMetrics()
    }

    func handlePickedAssets(_ inputs: [IndexedAssetInput]) async {
        guard !inputs.isEmpty else {
            applyIndexFailure(PSError.invalidInput("未读取到可用图片，请重新选择"))
            return
        }

        do {
            resetSearchPresentation(keepQuery: true)
            buildState = .preparing
            await requestPhotoLibraryAccessIfNeeded(for: inputs)

            let nextState = try await indexEngine.addAssetsAndRebuild(inputs)
            buildState = nextState
            try await refreshImportedAssets()
        } catch {
            applyIndexFailure(error)
        }
    }

    func rebuildIndexFromImportedAssets() async {
        guard canRebuildFromImportedAssets else { return }

        do {
            resetSearchPresentation(keepQuery: true)
            buildState = .preparing
            await requestPhotoLibraryAccessIfNeeded(for: indexedAssets)
            let nextState = try await indexEngine.rebuildImportedAssets()
            buildState = nextState
            try await refreshImportedAssets()
        } catch {
            applyIndexFailure(error)
            await refreshPerformanceMetrics()
        }
    }

    func presentImportFailure(_ error: Error) {
        applyIndexFailure(error)
    }

    func performSearch() async {
        let query = trimmedQuery
        guard !query.isEmpty else { return }

        guard isIndexReady else {
            searchResults = []
            hasAttemptedSearch = false
            searchFailure = TextImageFeedback(
                systemImage: "tray.and.arrow.down",
                title: "索引还没准备好",
                detail: indexedCount > 0
                    ? "请先完成索引构建，再开始搜索。"
                    : "请先选择图片并建立索引。",
                tone: .warning,
                actionTitle: nil
            )
            await refreshPerformanceMetrics()
            return
        }

        isSearching = true
        searchFailure = nil
        searchResults = []
        hasAttemptedSearch = false
        lastSubmittedQuery = query

        do {
            Logger.search.info(
                "开始回填搜索结果，查询: \(query)，已导入 \(self.indexedCount) 张，系统相册绑定 \(self.photoLibraryBackedCount) 张"
            )
            let results = try await searchEngine.search(text: query, topK: 12)
            let previewStartedAt = ContinuousClock.now
            var viewData: [TextSearchResultItem] = []
            var photoLibraryResolvedCount = 0
            viewData.reserveCapacity(results.count)

            for result in results {
                let resolvedPreview = await resolvePreview(for: result.assetLocalIdentifier)
                if resolvedPreview.sourceLabel == "系统相册" {
                    photoLibraryResolvedCount += 1
                }
                viewData.append(
                    TextSearchResultItem(
                        assetLocalIdentifier: result.assetLocalIdentifier,
                        displayTitle: resolvedPreview.displayTitle,
                        sourceLabel: resolvedPreview.sourceLabel,
                        score: result.score,
                        previewData: resolvedPreview.previewData
                    )
                )
            }

            await performanceStore.record(
                .previewResolution,
                duration: previewStartedAt.duration(to: .now),
                detail: "结果 \(viewData.count) 张，系统相册直读 \(photoLibraryResolvedCount) 张"
            )

            searchResults = viewData
            hasAttemptedSearch = true
        } catch {
            searchResults = []
            hasAttemptedSearch = true
            searchFailure = makeSearchFailure(for: error)
        }

        await refreshPerformanceMetrics()
        isSearching = false
    }

    func retrySearch() async {
        guard !trimmedQuery.isEmpty else { return }
        await performSearch()
    }

    func clearIndex() async {
        do {
            try await indexEngine.clearAll()
            indexedAssets = []
            photoLibraryAccessState = await photoLibraryAssetProvider.currentAccessState()
            resetSearchPresentation(keepQuery: true)
            buildState = .idle
            await refreshPerformanceMetrics()
        } catch {
            applyIndexFailure(error)
            await refreshPerformanceMetrics()
        }
    }

    private func resumeInterruptedBuild() async throws {
        buildState = .preparing
        let nextState = try await indexEngine.resumeBuildIfNeeded()
        buildState = nextState
        try await refreshImportedAssets()
    }

    private func refreshImportedAssets() async throws {
        let startedAt = ContinuousClock.now
        indexedAssets = try await indexEngine.loadImportedAssets()
        photoLibraryAccessState = await photoLibraryAssetProvider.currentAccessState()
        await performanceStore.record(
            .assetRefresh,
            duration: startedAt.duration(to: .now),
            detail: "已导入 \(indexedCount) 张，系统相册绑定 \(photoLibraryBackedCount) 张，权限 \(photoLibraryAccessState.metricsLabel)"
        )
        await refreshPerformanceMetrics()
    }

    private func requestPhotoLibraryAccessIfNeeded(for inputs: [IndexedAssetInput]) async {
        let requiresPhotoLibraryAccess = inputs.contains {
            ($0.photoLibraryAssetIdentifier?.isEmpty == false) || ($0.assetLocalIdentifier?.isEmpty == false)
        }
        guard requiresPhotoLibraryAccess else { return }

        let nextState = await photoLibraryAssetProvider.requestReadAccessIfNeeded()
        photoLibraryAccessState = nextState
    }

    private func requestPhotoLibraryAccessIfNeeded(for assets: [StoredIndexedAsset]) async {
        guard assets.contains(where: \.isPhotoLibraryBacked) else { return }

        let nextState = await photoLibraryAssetProvider.requestReadAccessIfNeeded()
        photoLibraryAccessState = nextState
    }

    private func refreshPerformanceMetrics() async {
        performanceMetrics = await performanceStore.metrics()
    }

    private func resetSearchPresentation(keepQuery: Bool) {
        searchResults = []
        searchFailure = nil
        hasAttemptedSearch = false
        lastSubmittedQuery = ""

        if !keepQuery {
            queryText = ""
        }
    }

    private func applyIndexFailure(_ error: Error) {
        resetSearchPresentation(keepQuery: true)
        buildState = .failed(message: userFacingIndexFailure(for: error))
    }

    private func resolvePreview(for assetLocalIdentifier: String) async -> PhotoLibraryPreviewPayload {
        let storedAsset = indexedAssets.first { $0.assetLocalIdentifier == assetLocalIdentifier }

        // 所有图片预览必须从系统相册获取
        guard let photoLibraryAssetIdentifier = storedAsset?.photoLibraryAssetIdentifier,
              let photoLibraryPayload = await photoLibraryAssetProvider.previewResource(for: photoLibraryAssetIdentifier) else {
            // 系统相册不可用，返回占位符
            return PhotoLibraryPreviewPayload(
                displayTitle: fallbackDisplayTitle(for: storedAsset, assetLocalIdentifier: assetLocalIdentifier),
                sourceLabel: "系统相册不可用",
                previewData: nil
            )
        }

        return PhotoLibraryPreviewPayload(
            displayTitle: photoLibraryPayload.displayTitle,
            sourceLabel: "系统相册",
            previewData: photoLibraryPayload.previewData
        )
    }

    private func fallbackSourceLabel(for asset: StoredIndexedAsset?) -> String {
        // 不再区分本地缓存，统一为系统相册不可用
        return "系统相册不可用"
    }

    private func fallbackDisplayTitle(for asset: StoredIndexedAsset?, assetLocalIdentifier: String) -> String {
        guard let asset, asset.isPhotoLibraryBacked else {
            return "图片资源不可用"
        }
        
        let prefix = String(assetLocalIdentifier.prefix(8))
        return prefix.isEmpty ? "系统相册图片" : "系统相册图片 \(prefix)"
    }

    private func statusFailureDetail(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "上次索引构建没有完成，请使用已导入图片重新建索引，必要时清空后重试。"
        }

        if trimmed.contains("模型") || trimmed.contains("推理") {
            return "模型暂时不可用，请稍后重试；如果持续失败，可重新打开应用后再试。"
        }
        if trimmed.contains("存储") || trimmed.contains("vectors") || trimmed.contains("manifest") {
            return "本地索引文件异常，请使用已导入图片重新建索引；必要时清空后再试。"
        }
        if trimmed.contains("系统相册") || trimmed.contains("相册") {
            return "系统相册资源当前不可用，请检查相册权限或资源状态。"
        }
        if trimmed.contains("资源") || trimmed.contains("sidecar") || trimmed.contains("不可读") {
            return "本地图片或索引资源缺失，请使用已导入图片重新建索引。"
        }
        if trimmed.contains("图片") || trimmed.contains("输入") {
            return trimmed
        }
        return "上次索引构建没有完成：\(trimmed)"
    }

    private func userFacingIndexFailure(for error: Error) -> String {
        guard let psError = error as? PSError else {
            return "索引处理失败，请稍后重试；如果持续失败，可清空后重新建立索引。"
        }

        switch psError {
        case .invalidInput(let detail):
            return detail
        case .modelNotFound, .modelLoadFailed, .inferenceFailed, .invalidModelOutput, .serviceNotReady:
            return "模型暂时不可用，请稍后重试；如果持续失败，可重新打开应用。"
        case .resourceNotFound, .resourceUnreadable:
            return "图片资源读取失败，请检查系统相册权限或使用已导入图片重新建索引。"
        case .storageCorrupted:
            return "本地索引文件异常，请使用已导入图片重新建索引；必要时清空后重试。"
        case .unsupportedOperation:
            return "当前操作暂不支持，请更换操作方式后重试。"
        case .unknown:
            return "索引处理失败，请稍后重试；如果持续失败，可清空后重新建立索引。"
        }
    }

    private func makeSearchFailure(for error: Error) -> TextImageFeedback {
        guard let psError = error as? PSError else {
            return TextImageFeedback(
                systemImage: "exclamationmark.triangle",
                title: "搜索失败",
                detail: "本次搜索没有完成，请稍后重试。",
                tone: .error,
                actionTitle: "重试搜索"
            )
        }

        switch psError {
        case .invalidInput(let detail):
            return TextImageFeedback(
                systemImage: "text.cursor",
                title: "搜索内容有问题",
                detail: detail,
                tone: .warning,
                actionTitle: nil
            )
        case .serviceNotReady, .modelNotFound, .modelLoadFailed, .inferenceFailed, .invalidModelOutput:
            return TextImageFeedback(
                systemImage: "brain.head.profile",
                title: "模型暂时不可用",
                detail: "文本向量生成失败，请稍后重试；如果持续失败，可重新打开应用。",
                tone: .error,
                actionTitle: "重试搜索"
            )
        case .storageCorrupted:
            return TextImageFeedback(
                systemImage: "externaldrive.badge.exclamationmark",
                title: "本地索引异常",
                detail: "索引文件无法正常读取，请先重新建立索引后再搜索。",
                tone: .error,
                actionTitle: nil
            )
        case .resourceNotFound, .resourceUnreadable:
            return TextImageFeedback(
                systemImage: "photo.badge.exclamationmark",
                title: "结果资源读取失败",
                detail: "搜索已完成，但真实图库资源或本地缓存暂时不可用；你可以重试搜索或重新建立索引。",
                tone: .warning,
                actionTitle: "重试搜索"
            )
        case .unsupportedOperation:
            return TextImageFeedback(
                systemImage: "hand.raised",
                title: "当前搜索暂不支持",
                detail: "请调整操作方式后重试。",
                tone: .warning,
                actionTitle: nil
            )
        case .unknown:
            return TextImageFeedback(
                systemImage: "exclamationmark.triangle",
                title: "搜索失败",
                detail: "本次搜索没有完成，请稍后重试。",
                tone: .error,
                actionTitle: "重试搜索"
            )
        }
    }
}
