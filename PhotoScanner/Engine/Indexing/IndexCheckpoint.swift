import Foundation

enum IndexCheckpointStage: String, Sendable, Codable {
    case idle
    case building
    case ready
    case failed
}

struct IndexCheckpoint: Sendable, Codable, Equatable {
    let stage: IndexCheckpointStage
    let candidateAssetIdentifiers: [String]
    let completedCount: Int
    let totalCount: Int
    let message: String?
    let updatedAt: Date

    var progress: IndexBuildProgress? {
        guard totalCount > 0 else { return nil }
        return try? IndexBuildProgress(completedCount: completedCount, totalCount: totalCount)
    }

    static func building(
        candidateAssetIdentifiers: [String],
        completedCount: Int,
        totalCount: Int,
        updatedAt: Date = Date()
    ) -> IndexCheckpoint {
        IndexCheckpoint(
            stage: .building,
            candidateAssetIdentifiers: candidateAssetIdentifiers,
            completedCount: completedCount,
            totalCount: totalCount,
            message: nil,
            updatedAt: updatedAt
        )
    }

    static func failed(
        candidateAssetIdentifiers: [String],
        completedCount: Int,
        totalCount: Int,
        message: String,
        updatedAt: Date = Date()
    ) -> IndexCheckpoint {
        IndexCheckpoint(
            stage: .failed,
            candidateAssetIdentifiers: candidateAssetIdentifiers,
            completedCount: completedCount,
            totalCount: totalCount,
            message: message,
            updatedAt: updatedAt
        )
    }
}
