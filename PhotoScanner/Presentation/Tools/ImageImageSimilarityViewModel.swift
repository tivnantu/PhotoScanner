//
// ImageImageSimilarityViewModel.swift
// PhotoScanner
//
// 图图相似度计算的 ViewModel
//

import Foundation
import SwiftUI
import PhotosUI

@MainActor
@Observable
final class ImageImageSimilarityViewModel {
    
    // MARK: - 依赖
    
    private let embeddingService: EmbeddingService
    
    // MARK: - 状态
    
    enum State {
        case idle
        case loading
        case loaded(similarity: Float)
        case error(String)
    }
    
    var state: State = .idle
    
    // 输入
    var selectedImage1: UIImage?
    var selectedImage2: UIImage?
    
    // MARK: - 初始化
    
    init(services: AppServices) {
        self.embeddingService = services.embeddingService
    }
    
    // MARK: - 操作
    
    /// 计算相似度
    func computeSimilarity() async {
        // 验证输入
        guard let image1 = selectedImage1 else {
            state = .error("请先选择第一张图片")
            return
        }
        
        guard let image2 = selectedImage2 else {
            state = .error("请先选择第二张图片")
            return
        }
        
        // 开始计算
        state = .loading
        
        do {
            // 转换图片为 Data
            guard let imageData1 = image1.jpegData(compressionQuality: 0.8),
                  let imageData2 = image2.jpegData(compressionQuality: 0.8) else {
                state = .error("图片格式转换失败")
                return
            }
            
            // 获取两张图片的 embedding
            async let embedding1 = embeddingService.embedImage(imageData1)
            async let embedding2 = embeddingService.embedImage(imageData2)
            
            let (emb1, emb2) = try await (embedding1, embedding2)
            
            // 计算余弦相似度
            let similarity = try cosineSimilarity(emb1, emb2)
            
            state = .loaded(similarity: similarity)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// 重置状态
    func reset() {
        state = .idle
        selectedImage1 = nil
        selectedImage2 = nil
    }
    
    // MARK: - 辅助方法
    
    /// 计算余弦相似度
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) throws -> Float {
        guard !a.isEmpty, !b.isEmpty else {
            throw PSError.invalidModelOutput("向量不能为空")
        }
        
        guard a.count == b.count else {
            throw PSError.invalidModelOutput("向量维度不匹配")
        }
        
        let dot = zip(a, b).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        
        let normA = sqrt(a.reduce(Float.zero) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(Float.zero) { $0 + $1 * $1 })
        
        guard normA > 0, normB > 0 else {
            throw PSError.invalidModelOutput("向量范数为零")
        }
        
        return dot / (normA * normB)
    }
}
