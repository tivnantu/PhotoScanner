import Foundation
@testable import PhotoScanner

struct TextValidationOutput {
    let tokenizerResults: [ChineseCLIPBaselineValidationReport.TokenizerResult]
    let embeddingResults: [ChineseCLIPBaselineValidationReport.EmbeddingResult]
    let actualEmbeddings: [String: [Float]]
}

enum ChineseCLIPBaselineTextValidator {
    static func validate(
        _ textCases: [ChineseCLIPBaseline.TextCase],
        tolerances: ChineseCLIPBaseline.Tolerances,
        tokenizer: ChineseCLIPTokenizer,
        embeddingService: EmbeddingService
    ) async throws -> TextValidationOutput {
        var tokenizerResults: [ChineseCLIPBaselineValidationReport.TokenizerResult] = []
        var embeddingResults: [ChineseCLIPBaselineValidationReport.EmbeddingResult] = []
        var actualEmbeddings: [String: [Float]] = [:]

        for textCase in textCases {
            let actualTokenIDs = tokenizer.encode(textCase.text)
            let firstMismatchIndex = BaselineVectorMath.firstMismatchIndex(
                expected: textCase.tokenIDs,
                actual: actualTokenIDs
            )
            let tokenizerPassed = tolerances.tokenIDsExactMatch ? (firstMismatchIndex == nil) : true

            tokenizerResults.append(
                .init(
                    caseID: textCase.id,
                    passed: tokenizerPassed,
                    expectedCount: textCase.tokenIDs.count,
                    actualCount: actualTokenIDs.count,
                    firstMismatchIndex: firstMismatchIndex
                )
            )

            let actualEmbedding = try await embeddingService.embedText(textCase.text)
            actualEmbeddings[textCase.id] = actualEmbedding

            let cosine = BaselineVectorMath.cosineSimilarity(actualEmbedding, textCase.textEmbedding)
            embeddingResults.append(
                .init(
                    caseID: textCase.id,
                    passed: cosine >= tolerances.textEmbeddingCosineMin,
                    cosine: cosine,
                    minimumCosine: tolerances.textEmbeddingCosineMin
                )
            )
        }

        return TextValidationOutput(
            tokenizerResults: tokenizerResults,
            embeddingResults: embeddingResults,
            actualEmbeddings: actualEmbeddings
        )
    }
}
