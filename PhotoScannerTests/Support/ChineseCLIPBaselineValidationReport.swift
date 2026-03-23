import Foundation

struct ChineseCLIPBaselineValidationReport: Sendable {
    let tokenizerResults: [TokenizerResult]
    let textEmbeddingResults: [EmbeddingResult]
    let imagePreprocessResults: [ImagePreprocessResult]
    let imageEmbeddingResults: [EmbeddingResult]
    let similarityResults: [SimilarityResult]

    var tokenizerPassed: Bool {
        tokenizerResults.allSatisfy(\.passed)
    }

    var textEmbeddingPassed: Bool {
        textEmbeddingResults.allSatisfy(\.passed)
    }

    var imagePreprocessPassed: Bool {
        imagePreprocessResults.allSatisfy(\.passed)
    }

    var imageEmbeddingPassed: Bool {
        imageEmbeddingResults.allSatisfy(\.passed)
    }

    var similarityPassed: Bool {
        similarityResults.allSatisfy(\.passed)
    }

    var isPassing: Bool {
        tokenizerPassed
            && textEmbeddingPassed
            && imagePreprocessPassed
            && imageEmbeddingPassed
            && similarityPassed
    }

    var failureMessages: [String] {
        tokenizerFailureMessages
            + textEmbeddingFailureMessages
            + imagePreprocessFailureMessages
            + imageEmbeddingFailureMessages
            + similarityFailureMessages
    }

    private var tokenizerFailureMessages: [String] {
        tokenizerResults.compactMap { result in
            guard !result.passed else { return nil }
            let mismatchDescription = result.firstMismatchIndex.map(String.init) ?? "nil"
            return "Tokenizer case=\(result.caseID) 失败，expectedCount=\(result.expectedCount), actualCount=\(result.actualCount), firstMismatchIndex=\(mismatchDescription)"
        }
    }

    private var textEmbeddingFailureMessages: [String] {
        textEmbeddingResults.compactMap { result in
            guard !result.passed else { return nil }
            return "Text embedding case=\(result.caseID) 失败，cosine=\(result.cosine), min=\(result.minimumCosine)"
        }
    }

    private var imagePreprocessFailureMessages: [String] {
        imagePreprocessResults.compactMap { result in
            guard !result.passed else { return nil }
            return "Image preprocess case=\(result.caseID) 失败，cosine=\(result.cosine), min=\(result.minimumCosine), maxAbsDiff=\(result.maximumAbsoluteDifference), limit=\(result.maximumAllowedAbsoluteDifference)"
        }
    }

    private var imageEmbeddingFailureMessages: [String] {
        imageEmbeddingResults.compactMap { result in
            guard !result.passed else { return nil }
            return "Image embedding case=\(result.caseID) 失败，cosine=\(result.cosine), min=\(result.minimumCosine)"
        }
    }

    private var similarityFailureMessages: [String] {
        similarityResults.compactMap { result in
            guard !result.passed else { return nil }
            return "Similarity case=\(result.caseID) 失败，expected=\(result.expected), actual=\(result.actual), absDiff=\(result.absoluteDifference), max=\(result.maximumDifference)"
        }
    }

    struct TokenizerResult: Sendable {
        let caseID: String
        let passed: Bool
        let expectedCount: Int
        let actualCount: Int
        let firstMismatchIndex: Int?
    }

    struct EmbeddingResult: Sendable {
        let caseID: String
        let passed: Bool
        let cosine: Float
        let minimumCosine: Float
    }

    struct ImagePreprocessResult: Sendable {
        let caseID: String
        let passed: Bool
        let cosine: Float
        let minimumCosine: Float
        let maximumAbsoluteDifference: Float
        let maximumAllowedAbsoluteDifference: Float
    }

    struct SimilarityResult: Sendable {
        let caseID: String
        let passed: Bool
        let expected: Float
        let actual: Float
        let absoluteDifference: Float
        let maximumDifference: Float
    }
}
