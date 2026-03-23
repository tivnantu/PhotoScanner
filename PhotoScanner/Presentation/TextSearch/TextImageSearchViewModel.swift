import Foundation
import Observation

struct TextSearchResultItem: Identifiable {
    let assetLocalIdentifier: String
    let score: Float
    let previewData: Data?

    var id: String {
        assetLocalIdentifier
    }
}

@Observable
@MainActor
final class TextImageSearchViewModel {
    var buildState: IndexBuildState = .idle
    var queryText: String = ""
    var isSearching = false
    var searchMessage: String?
    var indexedAssets: [StoredIndexedAsset] = []
    var searchResults: [TextSearchResultItem] = []

    var canSearch: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var statusTitle: String {
        switch buildState {
        case .idle:
            return "索引尚未建立"
        case .preparing:
            return "正在准备索引构建"
        case .building(let progress):
            return "正在构建索引（\(progress.completedCount)/\(progress.totalCount)）"
        case .ready(let manifest):
            return "索引已就绪（\(manifest.itemCount) 张）"
        case .failed:
            return "索引构建失败"
        }
    }

    var statusDetail: String {
        switch buildState {
        case .idle:
            return "先选择几张图片，建立本地向量索引后再做文搜图。"
        case .preparing:
            return "正在整理导入图片与恢复构建状态。"
        case .building(let progress):
            return "已完成 \(progress.completedCount) / \(progress.totalCount) 张图片 embedding。"
        case .ready:
            return "查询阶段会直接读取已索引向量，不会重新跑图片 embedding。"
        case .failed(let message):
            return message
        }
    }

    private let indexEngine: IndexEngine
    private let searchEngine: SearchEngine
    private var hasInitialized = false

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
            buildState = .failed(message: error.localizedDescription)
        }
    }

    func handlePickedImages(_ images: [Data]) async {
        guard !images.isEmpty else { return }

        do {
            let inputs = try images.map { try IndexedAssetInput(imageData: $0) }
            guard !inputs.isEmpty else {
                throw PSError.invalidInput("未读取到任何图片数据")
            }

            searchResults = []
            searchMessage = nil
            buildState = .preparing

            let nextState = try await indexEngine.addAssetsAndRebuild(inputs)
            buildState = nextState
            indexedAssets = try await indexEngine.loadImportedAssets()
        } catch {
            buildState = .failed(message: error.localizedDescription)
        }
    }

    func performSearch() async {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        searchMessage = nil

        do {
            let results = try await searchEngine.search(text: query, topK: 12)
            var viewData: [TextSearchResultItem] = []
            viewData.reserveCapacity(results.count)

            for result in results {
                let previewData = try await indexEngine.loadImageData(for: result.assetLocalIdentifier)
                viewData.append(
                    TextSearchResultItem(
                        assetLocalIdentifier: result.assetLocalIdentifier,
                        score: result.score,
                        previewData: previewData
                    )
                )
            }

            searchResults = viewData
            searchMessage = viewData.isEmpty ? "没有命中结果，试试换一个描述词。" : nil
        } catch {
            searchResults = []
            searchMessage = error.localizedDescription
        }

        isSearching = false
    }

    func clearIndex() async {
        do {
            try await indexEngine.clearAll()
            indexedAssets = []
            searchResults = []
            searchMessage = nil
            buildState = .idle
        } catch {
            buildState = .failed(message: error.localizedDescription)
        }
    }

    private func resumeInterruptedBuild() async throws {
        buildState = .preparing
        let nextState = try await indexEngine.resumeBuildIfNeeded()
        buildState = nextState
        indexedAssets = try await indexEngine.loadImportedAssets()
    }
}
