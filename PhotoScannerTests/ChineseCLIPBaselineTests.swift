import Foundation
import Testing
@testable import PhotoScanner

@Suite("ChineseCLIP Baseline")
struct ChineseCLIPBaselineTests {
    @MainActor
    @Test("Python 参考输出与 iOS 侧保持一致")
    func pythonBaselineConsistency() async throws {
        let baseline = try ChineseCLIPBaseline.load(from: PhotoScannerTestResources.baselineFileURL())
        let report = try await withEmbeddingService { embeddingService in
            try await ChineseCLIPBaselineValidator.validate(
                baseline: baseline,
                embeddingService: embeddingService
            )
        }

        assertBaselineReport(report)
    }

    private func withEmbeddingService<T>(
        _ body: (EmbeddingService) async throws -> T
    ) async throws -> T {
        let embeddingService = EmbeddingService(plugin: ChineseCLIPPlugin())

        do {
            let result = try await body(embeddingService)
            await embeddingService.shutdown()
            return result
        } catch {
            await embeddingService.shutdown()
            throw error
        }
    }

    private func assertBaselineReport(_ report: ChineseCLIPBaselineValidationReport) {
        #expect(report.tokenizerPassed)
        #expect(report.textEmbeddingPassed)
        #expect(report.imagePreprocessPassed)
        #expect(report.imageEmbeddingPassed)
        #expect(report.similarityPassed)
        #expect(report.failureMessages.isEmpty)
        #expect(report.isPassing)
    }
}
