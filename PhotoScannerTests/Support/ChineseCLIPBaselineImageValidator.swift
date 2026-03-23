import Foundation
@testable import PhotoScanner

struct ImageValidationOutput {
    let preprocessResults: [ChineseCLIPBaselineValidationReport.ImagePreprocessResult]
    let embeddingResults: [ChineseCLIPBaselineValidationReport.EmbeddingResult]
    let actualEmbeddings: [String: [Float]]
}

enum ChineseCLIPBaselineImageValidator {
    static func validate(
        _ imageCases: [ChineseCLIPBaseline.ImageCase],
        model: ChineseCLIPBaseline.ModelInfo,
        tolerances: ChineseCLIPBaseline.Tolerances,
        embeddingService: EmbeddingService
    ) async throws -> ImageValidationOutput {
        var preprocessResults: [ChineseCLIPBaselineValidationReport.ImagePreprocessResult] = []
        var embeddingResults: [ChineseCLIPBaselineValidationReport.EmbeddingResult] = []
        var actualEmbeddings: [String: [Float]] = [:]

        for imageCase in imageCases {
            let fixture = try loadFixture(for: imageCase)
            let actualTensor = try ChineseCLIPImagePreprocessor.preprocess(
                imageData: fixture.imageData,
                targetSize: model.imageSize,
                mean: model.imageMean,
                std: model.imageStd
            )

            let preprocessCosine = BaselineVectorMath.cosineSimilarity(actualTensor, fixture.expectedTensor)
            let preprocessMaxAbsDiff = BaselineVectorMath.maximumAbsoluteDifference(actualTensor, fixture.expectedTensor)
            let preprocessPassed = preprocessCosine >= tolerances.imagePreprocessCosineMin
                && preprocessMaxAbsDiff <= tolerances.imagePreprocessAbsDiffMax

            preprocessResults.append(
                .init(
                    caseID: imageCase.id,
                    passed: preprocessPassed,
                    cosine: preprocessCosine,
                    minimumCosine: tolerances.imagePreprocessCosineMin,
                    maximumAbsoluteDifference: preprocessMaxAbsDiff,
                    maximumAllowedAbsoluteDifference: tolerances.imagePreprocessAbsDiffMax
                )
            )

            let actualEmbedding = try await embeddingService.embedImage(fixture.imageData)
            actualEmbeddings[imageCase.id] = actualEmbedding

            let embeddingCosine = BaselineVectorMath.cosineSimilarity(actualEmbedding, imageCase.imageEmbedding)
            embeddingResults.append(
                .init(
                    caseID: imageCase.id,
                    passed: embeddingCosine >= tolerances.imageEmbeddingCosineMin,
                    cosine: embeddingCosine,
                    minimumCosine: tolerances.imageEmbeddingCosineMin
                )
            )
        }

        return ImageValidationOutput(
            preprocessResults: preprocessResults,
            embeddingResults: embeddingResults,
            actualEmbeddings: actualEmbeddings
        )
    }

    private static func loadFixture(for imageCase: ChineseCLIPBaseline.ImageCase) throws -> ImageFixture {
        let imageURL = try PhotoScannerTestResources.fixtureURL(relativePath: imageCase.image)
        let imageData = try Data(contentsOf: imageURL)

        let expectedTensorURL = try PhotoScannerTestResources.fixtureURL(
            relativePath: imageCase.preprocessedTensorFile
        )
        let expectedTensor = try BaselineVectorMath.loadFloat32Array(
            from: expectedTensorURL,
            expectedCount: imageCase.preprocessedTensorShape.reduce(1, *)
        )

        return ImageFixture(
            imageData: imageData,
            expectedTensor: expectedTensor
        )
    }
}

private struct ImageFixture {
    let imageData: Data
    let expectedTensor: [Float]
}
