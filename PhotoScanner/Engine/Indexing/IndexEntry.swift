//
// IndexEntry.swift
// PhotoScanner
//
// 单条索引记录。
// 当前阶段先直接持有 embedding，后续可演进为 offset / shard 引用。
//

import Foundation

struct IndexEntry: Sendable, Codable, Equatable {

    let assetLocalIdentifier: String
    let assetFingerprint: String
    let embedding: [Float]
    let createdAt: Date
    let updatedAt: Date

    var embeddingDimension: Int {
        embedding.count
    }

    init(
        assetLocalIdentifier: String,
        assetFingerprint: String,
        embedding: [Float],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        guard !assetLocalIdentifier.isEmpty else {
            throw PSError.invalidInput("assetLocalIdentifier 不能为空")
        }
        guard !assetFingerprint.isEmpty else {
            throw PSError.invalidInput("assetFingerprint 不能为空")
        }
        guard !embedding.isEmpty else {
            throw PSError.invalidInput("embedding 不能为空")
        }
        guard embedding.allSatisfy(\.isFinite) else {
            throw PSError.invalidModelOutput("embedding 包含非有限数值")
        }

        self.assetLocalIdentifier = assetLocalIdentifier
        self.assetFingerprint = assetFingerprint
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validate(against manifest: IndexManifest) throws {
        guard embeddingDimension == manifest.embeddingDimension else {
            throw PSError.invalidModelOutput(
                "索引条目维度不匹配，期望 \(manifest.embeddingDimension)，实际 \(embeddingDimension)"
            )
        }
    }
}
