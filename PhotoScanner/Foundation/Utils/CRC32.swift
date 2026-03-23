//
// CRC32.swift
// PhotoScanner
//
// CRC32 校验工具
// 用于数据完整性校验，检测文件损坏。
//

import Foundation

/// CRC32 校验工具
///
/// 使用查表法实现 CRC32 校验，用于检测数据完整性。
/// 性能约为逐字节计算的 8-10 倍。
///
/// ## 使用场景
/// - 向量索引文件校验
/// - 缓存数据校验
/// - 断点续传数据验证
///
/// ## 使用示例
/// ```swift
/// let data = try Data(contentsOf: fileURL)
/// let checksum = CRC32.checksum(data)
///
/// // 写入文件时保存校验和
/// var header = IndexHeader()
/// header.crc32 = checksum
///
/// // 读取文件时验证
/// let savedCRC = header.crc32
/// let computedCRC = CRC32.checksum(data)
/// guard savedCRC == computedCRC else {
///     throw PSError.storageCorrupted("CRC32 校验失败")
/// }
/// ```
enum CRC32 {

    /// CRC32 查找表（IEEE 802.3 标准多项式）
    ///
    /// 多项式: 0xEDB88320（反向表示）
    /// 生成方式: 对每个字节值计算 256 个 CRC 值
    private static let lookupTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    /// 计算 Data 的 CRC32 校验和
    ///
    /// - Parameter data: 待校验数据
    /// - Returns: CRC32 校验和
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ lookupTable[index]
        }
        return crc ^ 0xFFFFFFFF
    }

    /// 计算字节数组的 CRC32 校验和
    ///
    /// - Parameter bytes: 待校验字节数组
    /// - Returns: CRC32 校验和
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ lookupTable[index]
        }
        return crc ^ 0xFFFFFFFF
    }

    /// 验证数据的 CRC32 校验和
    ///
    /// - Parameters:
    ///   - data: 待验证数据
    ///   - expected: 期望的校验和
    /// - Returns: 是否匹配
    static func verify(_ data: Data, expected: UInt32) -> Bool {
        checksum(data) == expected
    }
}
