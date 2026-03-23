//
// IndexManifest.swift
// PhotoScanner
//
// 索引文件头信息。
// 描述一份索引由哪个模型生成、使用什么 schema、当前包含多少条记录。
//

import Foundation

struct IndexManifest: Sendable, Codable, Equatable {

    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let modelID: String
    let modelVersion: String
    let modelDisplayName: String
    let embeddingDimension: Int
    let imageSize: Int
    let contextLength: Int
    let modelFingerprint: String
    let resourceFingerprint: String
    let createdAt: Date
    let updatedAt: Date
    let itemCount: Int

    init(
        schemaVersion: Int = IndexManifest.currentSchemaVersion,
        modelID: String,
        modelVersion: String,
        modelDisplayName: String,
        embeddingDimension: Int,
        imageSize: Int,
        contextLength: Int,
        modelFingerprint: String,
        resourceFingerprint: String,
        createdAt: Date,
        updatedAt: Date,
        itemCount: Int
    ) throws {
        guard schemaVersion > 0 else {
            throw PSError.invalidInput("schemaVersion 必须大于 0")
        }
        guard !modelID.isEmpty else {
            throw PSError.invalidInput("modelID 不能为空")
        }
        guard !modelVersion.isEmpty else {
            throw PSError.invalidInput("modelVersion 不能为空")
        }
        guard !modelDisplayName.isEmpty else {
            throw PSError.invalidInput("modelDisplayName 不能为空")
        }
        guard embeddingDimension > 0 else {
            throw PSError.invalidInput("embeddingDimension 必须大于 0")
        }
        guard imageSize > 0 else {
            throw PSError.invalidInput("imageSize 必须大于 0")
        }
        guard contextLength > 0 else {
            throw PSError.invalidInput("contextLength 必须大于 0")
        }
        guard !modelFingerprint.isEmpty else {
            throw PSError.invalidInput("modelFingerprint 不能为空")
        }
        guard !resourceFingerprint.isEmpty else {
            throw PSError.invalidInput("resourceFingerprint 不能为空")
        }
        guard itemCount >= 0 else {
            throw PSError.invalidInput("itemCount 不能为负数")
        }

        self.schemaVersion = schemaVersion
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.modelDisplayName = modelDisplayName
        self.embeddingDimension = embeddingDimension
        self.imageSize = imageSize
        self.contextLength = contextLength
        self.modelFingerprint = modelFingerprint
        self.resourceFingerprint = resourceFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.itemCount = itemCount
    }

    init(
        modelDescriptor: ModelDescriptor,
        modelFingerprint: String,
        resourceFingerprint: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        itemCount: Int = 0
    ) throws {
        try self.init(
            modelID: modelDescriptor.id,
            modelVersion: modelDescriptor.version,
            modelDisplayName: modelDescriptor.displayName,
            embeddingDimension: modelDescriptor.embeddingDimension,
            imageSize: modelDescriptor.imageSize,
            contextLength: modelDescriptor.contextLength,
            modelFingerprint: modelFingerprint,
            resourceFingerprint: resourceFingerprint,
            createdAt: createdAt,
            updatedAt: updatedAt,
            itemCount: itemCount
        )
    }

    func withItemCount(_ itemCount: Int, updatedAt: Date = Date()) throws -> IndexManifest {
        try IndexManifest(
            schemaVersion: schemaVersion,
            modelID: modelID,
            modelVersion: modelVersion,
            modelDisplayName: modelDisplayName,
            embeddingDimension: embeddingDimension,
            imageSize: imageSize,
            contextLength: contextLength,
            modelFingerprint: modelFingerprint,
            resourceFingerprint: resourceFingerprint,
            createdAt: createdAt,
            updatedAt: updatedAt,
            itemCount: itemCount
        )
    }
}
