import Foundation
@testable import PhotoScanner

enum ChineseCLIPBaselineSimilarityValidator {
    static func validate(
        _ similarityCases: [ChineseCLIPBaseline.SimilarityCase],
        tolerances: ChineseCLIPBaseline.Tolerances,
        imageEmbeddings: [String: [Float]],
        textEmbeddings: [String: [Float]]
    ) throws -> [ChineseCLIPBaselineValidationReport.SimilarityResult] {
        try similarityCases.map { similarityCase in
            guard let imageEmbedding = imageEmbeddings[similarityCase.imageCaseID],
                  let textEmbedding = textEmbeddings[similarityCase.textCaseID] else {
                throw PSError.invalidInput("baseline 缺少用于相似度计算的 embedding 结果")
            }

            let actualSimilarity = BaselineVectorMath.dotProduct(imageEmbedding, textEmbedding)
            let absoluteDifference = abs(actualSimilarity - similarityCase.similarity)
            return .init(
                caseID: similarityCase.id,
                passed: absoluteDifference <= tolerances.similarityAbsDiffMax,
                expected: similarityCase.similarity,
                actual: actualSimilarity,
                absoluteDifference: absoluteDifference,
                maximumDifference: tolerances.similarityAbsDiffMax
            )
        }
    }
}
