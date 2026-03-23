import Foundation
import Observation
import Photos

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

@Observable
@MainActor
final class TextImageSearchViewModel {
    var buildState: IndexBuildState = .idle
    var queryText: String = ""
    var isSearching = false
    var indexedAssets: [StoredIndexedAsset] = []
    var searchResults: [TextSearchResultItem] = []
    var searchFailure: TextImageFeedback?
    var hasAttemptedSearch = false
    var lastSubmittedQuery: String = ""

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
            return indexedCount > 0 ? "已导入图片，等待建立索引" : "索引尚未建立"
        case .preparing:
            return "正在准备索引构建"
        case .building(let progress):
            return "正在构建索引（\(progress.completedCount)/\(progress.totalCount)）"
        case .ready(let manifest):
            return "索引已就绪（\(manifest.itemCount) 张）"
        case .failed:
            return "索引暂时不可用"
        }
    }

    var statusDetail: String {
        switch buildState {
        case .idle:
            if indexedCount > 0 {
                return "你已经导入了 \(indexedCount) 张图片，可以直接建立或重建本地向量索引。"
            }
            return "先选择几张图片，建立本地向量索引后再做文搜图。"
        case .preparing:
            return "正在整理导入图片、检查索引文件并准备恢复构建环境。"
        case .building(let progress):
            return "已完成 \(progress.completedCount) / \(progress.totalCount) 张图片 embedding，请稍候。"
        case .ready:
            return "查询阶段会直接读取已索引向量，不会重新跑图片 embedding。"
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

    var searchHintText: String {
        if isBuilding {
            return "索引构建中，完成后才能开始搜索。"
        }
        if !isIndexReady {
            return indexedCount > 0
                ? "请先完成索引构建，再开始搜索。"
                : "请先选择图片并建立索引。"
        }
        if trimmedQuery.isEmpty {
            return "输入一句自然语言描述，例如：海边日落、红色灯笼、雪山与湖泊。"
        }
        return "搜索会直接检索本地向量索引；如果能读取系统相册，会优先回填真实照片缩略图。"
    }

    var searchButtonTitle: String {
        isSearching ? "搜索中..." : "开始搜索"
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
    private var hasInitialized = false

    private var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(services: AppServices) {
        self.indexEngine = services.indexEngine
        self.searchEngine = services.searchEngine
    }

    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        buildState = await indexEngine.loadCurrentState()
        do {
            indexedAssets = try await indexEngine.loadImportedAssets()
            if case .building = buildState {
                try await resumeInterruptedBuild()
            }
        } catch {
            applyIndexFailure(error)
        }
    }

    func handlePickedAssets(_ inputs: [IndexedAssetInput]) async {
        guard !inputs.isEmpty else {
            applyIndexFailure(PSError.invalidInput("未读取到可用图片，请重新选择"))
            return
        }

        do {
            resetSearchPresentation(keepQuery: true)
            buildState = .preparing

            let nextState = try await indexEngine.addAssetsAndRebuild(inputs)
            buildState = nextState
            indexedAssets = try await indexEngine.loadImportedAssets()
        } catch {
            applyIndexFailure(error)
        }
    }

    func rebuildIndexFromImportedAssets() async {
        guard canRebuildFromImportedAssets else { return }

        do {
            resetSearchPresentation(keepQuery: true)
            buildState = .preparing
            let nextState = try await indexEngine.rebuildImportedAssets()
            buildState = nextState
            indexedAssets = try await indexEngine.loadImportedAssets()
        } catch {
            applyIndexFailure(error)
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
            return
        }

        isSearching = true
        searchFailure = nil
        searchResults = []
        hasAttemptedSearch = false
        lastSubmittedQuery = query

        do {
            let results = try await searchEngine.search(text: query, topK: 12)
            var viewData: [TextSearchResultItem] = []
            viewData.reserveCapacity(results.count)

            for result in results {
                let resolvedPreview = await resolvePreview(for: result.assetLocalIdentifier)
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

            searchResults = viewData
            hasAttemptedSearch = true
        } catch {
            searchResults = []
            hasAttemptedSearch = true
            searchFailure = makeSearchFailure(for: error)
        }

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
            resetSearchPresentation(keepQuery: true)
            buildState = .idle
        } catch {
            applyIndexFailure(error)
        }
    }

    private func resumeInterruptedBuild() async throws {
        buildState = .preparing
        let nextState = try await indexEngine.resumeBuildIfNeeded()
        buildState = nextState
        indexedAssets = try await indexEngine.loadImportedAssets()
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
        if let photoLibraryPayload = await loadPhotoLibraryPreview(for: assetLocalIdentifier) {
            let fallbackData: Data?
            if let previewData = photoLibraryPayload.previewData {
                fallbackData = previewData
            } else {
                fallbackData = try? await indexEngine.loadImageData(for: assetLocalIdentifier)
            }

            return PhotoLibraryPreviewPayload(
                displayTitle: photoLibraryPayload.displayTitle,
                sourceLabel: photoLibraryPayload.sourceLabel,
                previewData: fallbackData
            )
        }

        let fallbackData = try? await indexEngine.loadImageData(for: assetLocalIdentifier)
        return PhotoLibraryPreviewPayload(
            displayTitle: fallbackDisplayTitle(for: assetLocalIdentifier),
            sourceLabel: "本地导入",
            previewData: fallbackData
        )
    }

    private func loadPhotoLibraryPreview(for assetLocalIdentifier: String) async -> PhotoLibraryPreviewPayload? {
        guard hasPhotoLibraryReadAccess else { return nil }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalIdentifier], options: nil)
        guard let asset = result.firstObject else { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
        let displayTitle = resources.first?.originalFilename ?? photoLibraryFallbackTitle(for: asset)
        let previewData = await requestPhotoLibraryPreviewData(for: asset)

        return PhotoLibraryPreviewPayload(
            displayTitle: displayTitle,
            sourceLabel: "系统相册",
            previewData: previewData
        )
    }

    private var hasPhotoLibraryReadAccess: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    private func requestPhotoLibraryPreviewData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func photoLibraryFallbackTitle(for asset: PHAsset) -> String {
        if let creationDate = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "系统相册图片 · \(formatter.string(from: creationDate))"
        }
        return "系统相册图片"
    }

    private func fallbackDisplayTitle(for assetLocalIdentifier: String) -> String {
        if assetLocalIdentifier.hasPrefix("asset-") {
            return "本地导入图片"
        }

        let prefix = String(assetLocalIdentifier.prefix(8))
        return prefix.isEmpty ? "本地导入图片" : "图片 \(prefix)"
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
            return "本地图片或索引资源读取失败，请使用已导入图片重新建索引。"
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
                detail: "搜索已完成，但部分本地资源无法读取；你可以重试搜索或重新建立索引。",
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
