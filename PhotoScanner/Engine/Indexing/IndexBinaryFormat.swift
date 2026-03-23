import Foundation

struct BinaryIndexRowMetadata: Sendable, Codable, Equatable {
    let assetLocalIdentifier: String
    let assetFingerprint: String
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(entry: IndexEntry) {
        self.assetLocalIdentifier = entry.assetLocalIdentifier
        self.assetFingerprint = entry.assetFingerprint
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }

    nonisolated func makeEntry(embedding: [Float]) throws -> IndexEntry {
        try IndexEntry(
            assetLocalIdentifier: assetLocalIdentifier,
            assetFingerprint: assetFingerprint,
            embedding: embedding,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum IndexBinaryFormat {
    nonisolated static let fileName = "vectors.f32.bin"
    nonisolated static let formatVersion: UInt32 = 1
    nonisolated static let headerSize = 36

    nonisolated private static let magic = Data([0x50, 0x53, 0x49, 0x58]) // PSIX

    struct ParsedFile: Sendable {
        let embeddingDimension: Int
        let itemCount: Int
        let rows: [BinaryIndexRowMetadata]
        let dataOffset: Int
        let mappedData: Data

        nonisolated func makeSnapshot(manifest: IndexManifest) throws -> IndexSnapshot {
            guard manifest.embeddingDimension == embeddingDimension else {
                throw PSError.storageCorrupted(
                    "向量文件维度与 manifest 不一致：\(embeddingDimension) != \(manifest.embeddingDimension)"
                )
            }
            guard manifest.itemCount == itemCount else {
                throw PSError.storageCorrupted(
                    "向量文件条目数与 manifest 不一致：\(itemCount) != \(manifest.itemCount)"
                )
            }

            var entries: [IndexEntry] = []
            entries.reserveCapacity(itemCount)

            for rowIndex in 0..<itemCount {
                let embedding = try loadEmbedding(rowIndex: rowIndex)
                let entry = try rows[rowIndex].makeEntry(embedding: embedding)
                entries.append(entry)
            }

            return try IndexSnapshot(manifest: manifest, entries: entries)
        }

        nonisolated func loadEmbedding(rowIndex: Int) throws -> [Float] {
            guard rowIndex >= 0, rowIndex < itemCount else {
                throw PSError.invalidInput("rowIndex 越界: \(rowIndex)")
            }

            let start = dataOffset + rowIndex * embeddingDimension * MemoryLayout<UInt32>.size
            var embedding: [Float] = []
            embedding.reserveCapacity(embeddingDimension)

            for elementIndex in 0..<embeddingDimension {
                let bits: UInt32 = try mappedData.loadLittleEndian(at: start + elementIndex * MemoryLayout<UInt32>.size)
                embedding.append(Float(bitPattern: bits))
            }

            return embedding
        }
    }

    nonisolated static func encode(snapshot: IndexSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let rows = snapshot.entries.map(BinaryIndexRowMetadata.init)
        let idTableData = try encoder.encode(rows)
        let alignedIDTableLength = align4(idTableData.count)

        var payload = Data(capacity: alignedIDTableLength + snapshot.entries.count * snapshot.manifest.embeddingDimension * 4)
        payload.append(idTableData)
        if alignedIDTableLength > idTableData.count {
            payload.append(Data(repeating: 0, count: alignedIDTableLength - idTableData.count))
        }

        for entry in snapshot.entries {
            for value in entry.embedding {
                payload.append(littleEndian: value.bitPattern)
            }
        }

        let crc32 = payload.crc32()

        var fileData = Data(capacity: headerSize + payload.count)
        fileData.append(magic)
        fileData.append(littleEndian: formatVersion)
        fileData.append(littleEndian: UInt32(snapshot.manifest.embeddingDimension))
        fileData.append(littleEndian: UInt64(snapshot.entries.count))
        fileData.append(littleEndian: UInt64(idTableData.count))
        fileData.append(littleEndian: crc32)
        fileData.append(littleEndian: UInt32(0))
        fileData.append(payload)
        return fileData
    }

    nonisolated static func parse(_ data: Data) throws -> ParsedFile {
        guard data.count >= headerSize else {
            throw PSError.storageCorrupted("向量文件长度不足，无法读取 Header")
        }

        let magicData = data.subdata(in: 0..<magic.count)
        guard magicData == magic else {
            throw PSError.storageCorrupted("向量文件 magic 不匹配")
        }

        let version: UInt32 = try data.loadLittleEndian(at: 4)
        guard version == formatVersion else {
            throw PSError.storageCorrupted("不支持的向量文件版本: \(version)")
        }

        let embeddingDimensionRaw: UInt32 = try data.loadLittleEndian(at: 8)
        let itemCountRaw: UInt64 = try data.loadLittleEndian(at: 12)
        let idTableLengthRaw: UInt64 = try data.loadLittleEndian(at: 20)
        let expectedCRC32: UInt32 = try data.loadLittleEndian(at: 28)

        let embeddingDimension = Int(embeddingDimensionRaw)
        let itemCount = Int(itemCountRaw)
        let idTableLength = Int(idTableLengthRaw)
        let alignedIDTableLength = align4(idTableLength)
        let dataOffset = headerSize + alignedIDTableLength
        let vectorByteCount = itemCount * embeddingDimension * MemoryLayout<UInt32>.size
        let expectedFileSize = dataOffset + vectorByteCount

        guard embeddingDimension > 0 else {
            throw PSError.storageCorrupted("向量文件 embeddingDimension 非法")
        }
        guard itemCount >= 0 else {
            throw PSError.storageCorrupted("向量文件 itemCount 非法")
        }
        guard idTableLength >= 0 else {
            throw PSError.storageCorrupted("向量文件 ID Table 长度非法")
        }
        guard data.count == expectedFileSize else {
            throw PSError.storageCorrupted(
                "向量文件长度异常，期望 \(expectedFileSize) 字节，实际 \(data.count) 字节"
            )
        }

        let payload = data.subdata(in: headerSize..<data.count)
        let actualCRC32 = payload.crc32()
        guard actualCRC32 == expectedCRC32 else {
            throw PSError.storageCorrupted(
                "向量文件 CRC32 校验失败，期望 \(expectedCRC32)，实际 \(actualCRC32)"
            )
        }

        let idTableRange = headerSize..<(headerSize + idTableLength)
        let idTableData = data.subdata(in: idTableRange)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let rows = try decoder.decode([BinaryIndexRowMetadata].self, from: idTableData)

        guard rows.count == itemCount else {
            throw PSError.storageCorrupted(
                "ID Table 条目数与 Header 不一致：\(rows.count) != \(itemCount)"
            )
        }

        return ParsedFile(
            embeddingDimension: embeddingDimension,
            itemCount: itemCount,
            rows: rows,
            dataOffset: dataOffset,
            mappedData: data
        )
    }

    nonisolated private static func align4(_ value: Int) -> Int {
        let remainder = value % 4
        return remainder == 0 ? value : value + (4 - remainder)
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
            append(contentsOf: rawBuffer)
        }
    }

    func loadLittleEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
        let length = MemoryLayout<T>.size
        guard offset >= 0, offset + length <= count else {
            throw PSError.storageCorrupted("读取固定宽度数据越界，offset=\(offset), length=\(length)")
        }

        let range = offset..<(offset + length)
        let value = subdata(in: range).withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: T.self)
        }
        return T(littleEndian: value)
    }

    func crc32() -> UInt32 {
        let polynomial: UInt32 = 0xEDB88320
        var crc: UInt32 = 0xFFFFFFFF

        for byte in self {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
        }

        return ~crc
    }
}
