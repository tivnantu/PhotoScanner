import Foundation
import CryptoKit

struct IndexedAssetInput: Sendable {
    let assetLocalIdentifier: String?
    let photoLibraryAssetIdentifier: String?
    let imageData: Data
    let createdAt: Date

    init(
        assetLocalIdentifier: String? = nil,
        imageData: Data,
        createdAt: Date = Date()
    ) throws {
        guard !imageData.isEmpty else {
            throw PSError.invalidInput("导入图片数据不能为空")
        }

        let normalizedIdentifier = assetLocalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assetLocalIdentifier = normalizedIdentifier
        self.photoLibraryAssetIdentifier = normalizedIdentifier
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

struct StoredIndexedAsset: Sendable, Codable, Equatable, Identifiable {
    let assetLocalIdentifier: String
    let photoLibraryAssetIdentifier: String?
    let assetFingerprint: String
    let createdAt: Date
    let updatedAt: Date

    var id: String {
        assetLocalIdentifier
    }

    var isPhotoLibraryBacked: Bool {
        guard let photoLibraryAssetIdentifier else { return false }
        return !photoLibraryAssetIdentifier.isEmpty
    }

    init(input: IndexedAssetInput, existing: StoredIndexedAsset? = nil, now: Date = Date()) {
        let fingerprint = IndexedAssetIdentity.sha256Hex(for: input.imageData)
        let sanitizedIdentifier = input.assetLocalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdentifier: String
        if let sanitizedIdentifier, !sanitizedIdentifier.isEmpty {
            resolvedIdentifier = sanitizedIdentifier
        } else {
            resolvedIdentifier = "asset-\(String(fingerprint.prefix(16)))"
        }

        self.assetLocalIdentifier = resolvedIdentifier
        self.photoLibraryAssetIdentifier = sanitizedIdentifier
        self.assetFingerprint = fingerprint
        self.createdAt = existing?.createdAt ?? input.createdAt
        self.updatedAt = now
    }
    
    /// 用于从持久化数据重建（无 imageData）
    init(
        assetLocalIdentifier: String,
        photoLibraryAssetIdentifier: String?,
        assetFingerprint: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.photoLibraryAssetIdentifier = photoLibraryAssetIdentifier
        self.assetFingerprint = assetFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum IndexedAssetIdentity {
    nonisolated static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fileStem(for identifier: String) -> String {
        sha256Hex(for: Data(identifier.utf8))
    }
}
