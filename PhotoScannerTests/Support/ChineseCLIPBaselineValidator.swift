import Foundation
import OSLog
@testable import PhotoScanner

enum ChineseCLIPBaselineValidator {
    static func validate(
        baseline: ChineseCLIPBaseline,
        embeddingService: EmbeddingService
    ) async throws -> ChineseCLIPBaselineValidationReport {
        try await embeddingService.initialize()

        let tokenizer = try ChineseCLIPTokenizer(
            vocabPath: BundleResource.vocabPath(),
            contextLength: baseline.model.contextLength
        )
        let textOutput = try await ChineseCLIPBaselineTextValidator.validate(
            baseline.textCases,
            tolerances: baseline.tolerances,
            tokenizer: tokenizer,
            embeddingService: embeddingService
        )
        let imageOutput = try await ChineseCLIPBaselineImageValidator.validate(
            baseline.imageCases,
            model: baseline.model,
            tolerances: baseline.tolerances,
            embeddingService: embeddingService
        )
        let similarityResults = try ChineseCLIPBaselineSimilarityValidator.validate(
            baseline.similarityCases,
            tolerances: baseline.tolerances,
            imageEmbeddings: imageOutput.actualEmbeddings,
            textEmbeddings: textOutput.actualEmbeddings
        )

        let report = ChineseCLIPBaselineValidationReport(
            tokenizerResults: textOutput.tokenizerResults,
            textEmbeddingResults: textOutput.embeddingResults,
            imagePreprocessResults: imageOutput.preprocessResults,
            imageEmbeddingResults: imageOutput.embeddingResults,
            similarityResults: similarityResults
        )

        let status = report.isPassing ? "通过" : "失败"
        Logger.model.info("ChineseCLIP 基线校验完成，结果: \(status)")
        return report
    }
}
