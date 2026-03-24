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

            Task {
                var items: [PHPickerResultItem] = []
                items.reserveCapacity(results.count)

                for result in results {
                    // 获取真实的 PHAsset localIdentifier
                    guard let assetIdentifier = result.assetIdentifier else {
                        continue
                    }

                    // 加载图片数据
                    if let data = await loadImageData(from: result.itemProvider) {
                        items.append(PHPickerResultItem(
                            assetIdentifier: assetIdentifier,
                            imageData: data
                        ))
                    }
                }

                await parent.onComplete(items)
            }
        }

        private func loadImageData(from itemProvider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { continuation in
                itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage,
                       let data = image.jpegData(compressionQuality: 0.9) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
