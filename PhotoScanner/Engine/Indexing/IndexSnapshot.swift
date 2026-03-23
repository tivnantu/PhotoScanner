//
// IndexSnapshot.swift
// PhotoScanner
//
// 一份完整索引快照：manifest + entries。
// 这是当前阶段最简单、最稳定的领域聚合形态。
//

import Foundation

struct IndexSnapshot: Sendable, Codable, Equatable {

    let manifest: IndexManifest
    let entries: [IndexEntry]

    var isEmpty: Bool {
        entries.isEmpty
    }

    init(manifest: IndexManifest, entries: [IndexEntry]) throws {
        guard manifest.itemCount == entries.count else {
            throw PSError.invalidInput(
                "manifest.itemCount 与 entries.count 不一致：\(manifest.itemCount) != \(entries.count)"
            )
        }

        try entries.forEach { try $0.validate(against: manifest) }

        self.manifest = manifest
        self.entries = entries
    }

    static func empty(
        modelDescriptor: ModelDescriptor,
        modelFingerprint: String,
        resourceFingerprint: String,
        createdAt: Date = Date()
    ) throws -> IndexSnapshot {
        let manifest = try IndexManifest(
            modelDescriptor: modelDescriptor,
            modelFingerprint: modelFingerprint,
            resourceFingerprint: resourceFingerprint,
            createdAt: createdAt,
            updatedAt: createdAt,
            itemCount: 0
        )
        return try IndexSnapshot(manifest: manifest, entries: [])
    }

    func replacingEntries(_ entries: [IndexEntry], updatedAt: Date = Date()) throws -> IndexSnapshot {
        let nextManifest = try manifest.withItemCount(entries.count, updatedAt: updatedAt)
        return try IndexSnapshot(manifest: nextManifest, entries: entries)
    }
}
