//
// PHPickerWrapper.swift
// PhotoScanner
//
// PHPicker 包装器，提供可靠的 PHAsset localIdentifier
// 解决 PhotosPickerItem.itemIdentifier 为 nil 的问题
//

import SwiftUI
import PhotosUI
import Photos
import OSLog
import UniformTypeIdentifiers

/// PHPicker 结果
struct PHPickerResultItem: Sendable {
    /// PHAsset localIdentifier（可靠）
    let assetIdentifier: String
    /// 图片数据
    let imageData: Data
}

/// PHPicker SwiftUI 包装器
struct PHPickerWrapper: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let selectionLimit: Int
    let onComplete: @Sendable ([PHPickerResultItem]) async -> Void

    init(
        isPresented: Binding<Bool>,
        selectionLimit: Int = 0,
        onComplete: @escaping @Sendable ([PHPickerResultItem]) async -> Void
    ) {
        self._isPresented = isPresented
        self.selectionLimit = selectionLimit
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = selectionLimit
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper

        init(_ parent: PHPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            guard !results.isEmpty else { return }

            Logger.ui.info("PHPicker: 开始处理 \(results.count) 个结果")

            Task { [weak self] in
                guard self != nil else {
                    Logger.ui.warning("PHPicker: self 已释放")
                    return
                }

                var items: [PHPickerResultItem] = []
                items.reserveCapacity(results.count)

                for (index, result) in results.enumerated() {
                    Logger.ui.info("PHPicker: 处理第 \(index + 1) 个结果，assetIdentifier: \(result.assetIdentifier ?? "nil")")

                    // 获取真实的 PHAsset localIdentifier
                    guard let assetIdentifier = result.assetIdentifier else {
                        Logger.ui.warning("PHPicker: assetIdentifier 为 nil")
                        continue
                    }

                    // 加载图片数据
                    if let data = await loadImageData(from: result.itemProvider) {
                        Logger.ui.info("PHPicker: 成功加载图片，大小 \(data.count) bytes")
                        items.append(PHPickerResultItem(
                            assetIdentifier: assetIdentifier,
                            imageData: data
                        ))
                        Logger.ui.info("PHPicker: items.count = \(items.count)")
                    } else {
                        Logger.ui.warning("PHPicker: 加载图片数据失败，assetIdentifier: \(assetIdentifier)")
                    }
                }

                Logger.ui.info("PHPicker: 处理完成，items.count = \(items.count)")
                if !items.isEmpty {
                    Logger.ui.info("PHPicker: 调用 onComplete")
                    await parent.onComplete(items)
                    Logger.ui.info("PHPicker: onComplete 调用完成")
                } else {
                    Logger.ui.warning("PHPicker: items 为空，不调用 onComplete")
                }
            }
        }

        private func loadImageData(from itemProvider: NSItemProvider) async -> Data? {
            // 先尝试直接加载 UIImage
            if let data = await loadImageAsUIImage(from: itemProvider) {
                return data
            }

            // 如果失败，尝试加载为 Data
            return await loadRawData(from: itemProvider)
        }

        private func loadImageAsUIImage(from itemProvider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { continuation in
                itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error = error {
                        Logger.ui.warning("PHPicker loadObject UIImage 错误: \(error.localizedDescription)")
                    }
                    if let image = object as? UIImage,
                       let data = image.jpegData(compressionQuality: 0.9) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        private func loadRawData(from itemProvider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { continuation in
                itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let error = error {
                        Logger.ui.warning("PHPicker loadDataRepresentation 错误: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
