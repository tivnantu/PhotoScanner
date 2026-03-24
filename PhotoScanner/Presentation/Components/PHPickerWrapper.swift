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
struct PHPickerResultItem: Sendable, Equatable {
    /// PHAsset localIdentifier（可靠）
    let assetIdentifier: String
    /// 图片数据
    let imageData: Data
    
    static func == (lhs: PHPickerResultItem, rhs: PHPickerResultItem) -> Bool {
        lhs.assetIdentifier == rhs.assetIdentifier && lhs.imageData == rhs.imageData
    }
}

/// PHPicker SwiftUI 包装器 - 使用 Binding 传递结果
struct PHPickerWrapper: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedItems: [PHPickerResultItem]
    let selectionLimit: Int

    init(
        isPresented: Binding<Bool>,
        selectedItems: Binding<[PHPickerResultItem]>,
        selectionLimit: Int = 1
    ) {
        self._isPresented = isPresented
        self._selectedItems = selectedItems
        self.selectionLimit = selectionLimit
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

            Task { @MainActor [weak self] in
                guard let self = self else {
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
                    } else {
                        Logger.ui.warning("PHPicker: 加载图片数据失败，assetIdentifier: \(assetIdentifier)")
                    }
                }

                Logger.ui.info("PHPicker: 处理完成，items.count = \(items.count)，直接设置 selectedItems")
                // 直接设置 Binding，不通过闭包传递
                parent.selectedItems = items
                Logger.ui.info("PHPicker: selectedItems 已设置，count = \(parent.selectedItems.count)")
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
