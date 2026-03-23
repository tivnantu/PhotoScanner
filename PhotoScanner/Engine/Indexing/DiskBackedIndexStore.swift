import Foundation
import OSLog

actor DiskBackedIndexStore: IndexStore {
    private let rootURL: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(rootURL: URL = DiskBackedIndexStore.defaultRootURL()) {
        self.rootURL = rootURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    nonisolated static func defaultRootURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("PhotoScannerIndex", isDirectory: true)
    }

    func vectorFileURL() -> URL {
        vectorsURL
    }

    func loadManifest() async throws -> IndexManifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        return try jsonDecoder.decode(IndexManifest.self, from: data)
    }

    func loadCheckpoint() async throws -> IndexCheckpoint? {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: checkpointURL)
        return try jsonDecoder.decode(IndexCheckpoint.self, from: data)
    }

    func saveCheckpoint(_ checkpoint: IndexCheckpoint) async throws {
        try ensureDirectoryStructure()
        let data = try jsonEncoder.encode(checkpoint)
        try data.write(to: checkpointURL, options: .atomic)
        Logger.index.debug("checkpoint 已更新，阶段: \(checkpoint.stage.rawValue), 进度: \(checkpoint.completedCount)/\(checkpoint.totalCount)")
    }

    func saveImportedAssets(_ inputs: [IndexedAssetInput]) async throws -> [StoredIndexedAsset] {
        guard !inputs.isEmpty else { return try await loadImportedAssets() }
        try ensureDirectoryStructure()

        var assetsByID = try Dictionary(
            uniqueKeysWithValues: try await loadImportedAssets().map { ($0.assetLocalIdentifier, $0) }
        )

        for input in inputs {
            let preferredIdentifier = input.assetLocalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = preferredIdentifier.flatMap { assetsByID[$0] }
            let asset = StoredIndexedAsset(input: input, existing: existing)
            let dataURL = importedAssetDataURL(for: asset.assetLocalIdentifier)
            try input.imageData.write(to: dataURL, options: .atomic)
            assetsByID[asset.assetLocalIdentifier] = asset
        }

        let allAssets = assetsByID.values.sorted { $0.assetLocalIdentifier < $1.assetLocalIdentifier }
        let data = try jsonEncoder.encode(allAssets)
        try data.write(to: assetsMetadataURL, options: .atomic)

        let photoLibraryBackedCount = allAssets.filter(\.isPhotoLibraryBacked).count
        Logger.index.info(
            "导入图片已更新，当前累计 \(allAssets.count) 张，系统相册绑定 \(photoLibraryBackedCount) 张，本地缓存 \(allAssets.count - photoLibraryBackedCount) 张"
        )
        return allAssets
    }

    func loadImportedAssets() async throws -> [StoredIndexedAsset] {
        guard FileManager.default.fileExists(atPath: assetsMetadataURL.path) else {
            return []
        }

        let data = try Data(contentsOf: assetsMetadataURL)
        let assets = try jsonDecoder.decode([StoredIndexedAsset].self, from: data)
        return assets.sorted { $0.assetLocalIdentifier < $1.assetLocalIdentifier }
    }

    func importedAssetData(for assetLocalIdentifier: String) async throws -> Data? {
        let url = importedAssetDataURL(for: assetLocalIdentifier)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func saveChunk(_ entry: IndexEntry) async throws {
        try ensureDirectoryStructure()
        let url = chunkFileURL(for: entry.assetLocalIdentifier)
        let data = try jsonEncoder.encode(entry)
        try data.write(to: url, options: .atomic)
        Logger.index.debug("chunk 已写入: \(entry.assetLocalIdentifier)")
    }

    func loadChunkEntries() async throws -> [IndexEntry] {
        guard FileManager.default.fileExists(atPath: chunksDirectoryURL.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: chunksDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [IndexEntry] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            let data = try Data(contentsOf: url)
            let entry = try jsonDecoder.decode(IndexEntry.self, from: data)
            entries.append(entry)
        }

        return entries.sorted { $0.assetLocalIdentifier < $1.assetLocalIdentifier }
    }

    func clearTransientBuildArtifacts() async throws {
        try ensureDirectoryStructure()
        try removeItemIfExists(at: manifestURL)
        try removeItemIfExists(at: vectorsURL)
        try removeItemIfExists(at: checkpointURL)
        try removeItemIfExists(at: chunksDirectoryURL)
        try FileManager.default.createDirectory(at: chunksDirectoryURL, withIntermediateDirectories: true)
    }

    func loadSnapshot() async throws -> IndexSnapshot? {
        guard let manifest = try await loadManifest() else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: vectorsURL.path) else {
            throw PSError.storageCorrupted("manifest 已存在，但缺少 vectors.f32.bin")
        }

        let data: Data
        do {
            data = try Data(contentsOf: vectorsURL, options: .mappedIfSafe)
        } catch {
            throw PSError.resourceUnreadable(path: vectorsURL.path, reason: error.localizedDescription)
        }

        let parsed = try IndexBinaryFormat.parse(data)
        return try parsed.makeSnapshot(manifest: manifest)
    }

    func saveSnapshot(_ snapshot: IndexSnapshot) async throws {
        try ensureDirectoryStructure()

        let manifestData = try jsonEncoder.encode(snapshot.manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        let vectorData = try IndexBinaryFormat.encode(snapshot: snapshot)
        try vectorData.write(to: vectorsURL, options: .atomic)

        try removeItemIfExists(at: checkpointURL)
        try removeItemIfExists(at: chunksDirectoryURL)
        try FileManager.default.createDirectory(at: chunksDirectoryURL, withIntermediateDirectories: true)

        Logger.index.info("磁盘索引已保存，条目数: \(snapshot.manifest.itemCount)")
    }

    func clear() async throws {
        try removeItemIfExists(at: rootURL)
        Logger.index.info("磁盘索引目录已清空")
    }

    private var manifestURL: URL {
        rootURL.appendingPathComponent("manifest.json")
    }

    private var checkpointURL: URL {
        rootURL.appendingPathComponent("checkpoint.json")
    }

    private var vectorsURL: URL {
        rootURL.appendingPathComponent(IndexBinaryFormat.fileName)
    }

    private var chunksDirectoryURL: URL {
        rootURL.appendingPathComponent("chunks", isDirectory: true)
    }

    private var assetsDirectoryURL: URL {
        rootURL.appendingPathComponent("assets", isDirectory: true)
    }

    private var assetsMetadataURL: URL {
        rootURL.appendingPathComponent("assets.json")
    }

    private func chunkFileURL(for assetLocalIdentifier: String) -> URL {
        chunksDirectoryURL
            .appendingPathComponent(IndexedAssetIdentity.fileStem(for: assetLocalIdentifier))
            .appendingPathExtension("json")
    }

    private func importedAssetDataURL(for assetLocalIdentifier: String) -> URL {
        assetsDirectoryURL
            .appendingPathComponent(IndexedAssetIdentity.fileStem(for: assetLocalIdentifier))
            .appendingPathExtension("bin")
    }

    private func ensureDirectoryStructure() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chunksDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
    }

    private func removeItemIfExists(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
