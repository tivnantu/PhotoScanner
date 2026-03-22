//
// SimilarityDebugViewModel.swift
// PhotoScanner
//
// 相似度验证页的状态管理。
// 这不是最终产品页，而是底模接入的验证台。
//

import Foundation
import SwiftUI
import PhotosUI
import OSLog

// MARK: - 页面状态

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

// MARK: - ViewModel

@Observable
@MainActor
final class SimilarityDebugViewModel {

    // MARK: - 公开状态

    var state: SimilarityDebugState = .idle
    var inputText: String = ""
    var selectedImageData: Data?
    var selectedImagePreview: Image?

    /// 是否可以点击计算按钮
    var canCompute: Bool {
        selectedImageData != nil && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && state != .loadingModel && state != .computing
    }

    // MARK: - 依赖

    private let embeddingService: EmbeddingService
    private let similarityEngine: SimilarityEngine

    // MARK: - 初始化

    init(services: AppServices) {
        self.embeddingService = services.embeddingService
        self.similarityEngine = services.similarityEngine
    }

    // MARK: - 操作

    /// 初始化模型（首次进入页面时调用）
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

    /// 计算图文相似度
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

    /// 处理用户选择的照片
    func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            selectedImageData = nil
            selectedImagePreview = nil
            return
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                // 生成预览
                if let uiImage = UIImage(data: data) {
                    selectedImagePreview = Image(uiImage: uiImage)
                }
            }
        } catch {
            Logger.ui.error("验证页: 加载照片失败 — \(error)")
        }
    }
}
