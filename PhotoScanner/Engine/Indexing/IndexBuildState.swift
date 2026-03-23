//
// IndexBuildState.swift
// PhotoScanner
//
// 索引构建状态模型。
// 当前先覆盖构建阶段最小状态，后续 UI 可直接消费。
//

import Foundation

struct IndexBuildProgress: Sendable, Codable, Equatable {

    let completedCount: Int
    let totalCount: Int

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    init(completedCount: Int, totalCount: Int) throws {
        guard completedCount >= 0 else {
            throw PSError.invalidInput("completedCount 不能为负数")
        }
        guard totalCount > 0 else {
            throw PSError.invalidInput("totalCount 必须大于 0")
        }
        guard completedCount <= totalCount else {
            throw PSError.invalidInput("completedCount 不能大于 totalCount")
        }

        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

enum IndexBuildState: Sendable, Equatable {
    case idle
    case preparing
    case building(progress: IndexBuildProgress)
    case ready(manifest: IndexManifest)
    case failed(message: String)
}
