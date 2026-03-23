import Foundation
import UIKit
@testable import PhotoScanner

/// Mock EmbeddingService for testing
actor MockEmbeddingService {
    var mockEmbedding: [Float] = Array(repeating: 0.5, count: 512)
    var shouldThrowError = false
    var embedImageCallCount = 0
    
    nonisolated init() {}
    
    func embedImage(_ data: Data) async throws -> [Float] {
        embedImageCallCount += 1
        
        if shouldThrowError {
            throw ImageSearchError.failedToEmbedImage
        }
        
        return mockEmbedding
    }
    
    func embedText(_ text: String) async throws -> [Float] {
        return mockEmbedding
    }
    
    func initialize() async throws {}
    
    var isReady: Bool { true }
}
