import Foundation
import SwiftUI
import PhotosUI
import OSLog

enum SimilarityDebugState: Equatable {
    case idle
    case loadingModel
    case computing
    case success(score: Float)
    case failure(message: String)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loadingModel, .loadingModel), (.computing, .computing):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.failure(let a), .failure(let b)):
            return a == b
        default:
            return false
        }
    }
}

@Observable
@MainActor
final class SimilarityDebugViewModel {

    var state: SimilarityDebugState = .idle
    var inputText: String = ""
    var selectedImageData: Data?
    var selectedImagePreview: Image?

    var canCompute: Bool {
        selectedImageData != nil
        && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && state != .loadingModel
        && state != .computing
    }

    private let embeddingService: EmbeddingService
    private let similarityEngine: SimilarityEngine

    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.similarityEngine = services.similarityEngine
    }

    func initializeModelIfNeeded() async {
        let isReady = await embeddingService.isReady
        guard !isReady else { return }

        state = .loadingModel
        do {
            try await embeddingService.initialize()
            state = .idle
            Logger.model.info("验证页: 模型初始化成功")
        } catch {
            state = .failure(message: "模型加载失败: \(error.localizedDescription)")
            Logger.model.error("验证页: 模型初始化失败 — \(error)")
        }
    }

    func computeSimilarity() async {
        guard let imageData = selectedImageData else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        state = .computing
        do {
            let score = try await similarityEngine.computeSimilarity(imageData: imageData, text: text)
            state = .success(score: score)
            Logger.search.info("验证页: 相似度 = \(score, format: .fixed(precision: 4)), 文本 = \(text)")
        } catch {
            state = .failure(message: error.localizedDescription)
            Logger.search.error("验证页: 计算失败 — \(error)")
        }
    }

    func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            selectedImageData = nil
            selectedImagePreview = nil
            return
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                if let uiImage = UIImage(data: data) {
                    selectedImagePreview = Image(uiImage: uiImage)
                }
            }
        } catch {
            Logger.ui.error("验证页: 加载照片失败 — \(error)")
        }
    }
}
