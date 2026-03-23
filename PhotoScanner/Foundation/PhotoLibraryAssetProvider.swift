import Foundation
import Photos

enum PhotoLibraryAccessState: Sendable, Equatable {
    case fullAccess
    case limitedAccess
    case notDetermined
    case unavailable

    var hasReadAccess: Bool {
        switch self {
        case .fullAccess, .limitedAccess:
            return true
        case .notDetermined, .unavailable:
            return false
        }
    }
}

struct PhotoLibraryPreviewResource: Sendable {
    let displayTitle: String
    let previewData: Data?
}

actor PhotoLibraryAssetProvider {
    func currentAccessState() -> PhotoLibraryAccessState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            return .fullAccess
        case .limited:
            return .limitedAccess
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func previewResource(for localIdentifier: String) async -> PhotoLibraryPreviewResource? {
        guard !localIdentifier.isEmpty else { return nil }
        guard (currentAccessState()).hasReadAccess else { return nil }
        guard let asset = fetchAsset(localIdentifier: localIdentifier) else { return nil }

        return PhotoLibraryPreviewResource(
            displayTitle: displayTitle(for: asset),
            previewData: await requestImageData(
                for: asset,
                deliveryMode: .fastFormat,
                resizeMode: .fast,
                allowsNetworkAccess: false
            )
        )
    }

    func originalImageData(for localIdentifier: String) async -> Data? {
        guard !localIdentifier.isEmpty else { return nil }
        guard (currentAccessState()).hasReadAccess else { return nil }
        guard let asset = fetchAsset(localIdentifier: localIdentifier) else { return nil }

        return await requestImageData(
            for: asset,
            deliveryMode: .highQualityFormat,
            resizeMode: .none,
            allowsNetworkAccess: false
        )
    }

    func containsAsset(with localIdentifier: String) -> Bool {
        guard !localIdentifier.isEmpty else { return false }
        guard (currentAccessState()).hasReadAccess else { return false }
        return fetchAsset(localIdentifier: localIdentifier) != nil
    }

    private func fetchAsset(localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    private func requestImageData(
        for asset: PHAsset,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode,
        allowsNetworkAccess: Bool
    ) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = resizeMode
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func displayTitle(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if let originalFilename = resources.first?.originalFilename, !originalFilename.isEmpty {
            return originalFilename
        }

        if let creationDate = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "系统相册图片 · \(formatter.string(from: creationDate))"
        }

        return "系统相册图片"
    }
}
