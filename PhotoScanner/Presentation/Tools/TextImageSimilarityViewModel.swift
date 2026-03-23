//
// TextImageSimilarityViewModel.swift
// PhotoScanner
//
// 图文相似度计算的 ViewModel
//

import Foundation
import SwiftUI
import PhotosUI

@MainActor
@Observable
final class TextImageSimilarityViewModel {
    
    // MARK: - 依赖
    
    private let similarityEngine: SimilarityEngine
    
    // MARK: - 状态
    
    enum State {
        case idle
        case loading
        case loaded(similarity: Float)
        case error(String)
    }
    
    var state: State = .idle
    
    // 输入
    var selectedImage: UIImage?
    var inputText: String = ""
    
    // MARK: - 初始化
    
    init(services: AppServices) {
        self.similarityEngine = services.similarityEngine
    }
    
    // MARK: - 操作
    
    /// 计算相似度
    func computeSimilarity() async {
        // 验证输入
        guard let image = selectedImage else {
            state = .error("请先选择图片")
            return
        }
        
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .error("请输入文本描述")
            return
        }
        
        // 开始计算
        state = .loading
        
        do {
            // 转换图片为 Data
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                state = .error("图片格式转换失败")
                return
            }
            
            // 调用相似度引擎
            let similarity = try await similarityEngine.computeSimilarity(
                imageData: imageData,
                text: text
            )
            
            state = .loaded(similarity: similarity)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// 重置状态
    func reset() {
        state = .idle
        selectedImage = nil
        inputText = ""
    }
}
