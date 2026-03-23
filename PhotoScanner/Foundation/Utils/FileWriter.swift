//
// FileWriter.swift
// PhotoScanner
//
// 文件写入工具
// 提供原子写入等安全写入方式，确保数据一致性。
//

import Foundation
import OSLog

/// 文件写入工具
///
/// 提供安全的文件写入方式，包括：
/// - 原子写入：先写入临时文件，再重命名，避免写入过程中崩溃导致数据损坏
/// - 追加写入：高效追加数据到文件末尾
///
/// ## 原子写入原理
/// 1. 创建临时文件（与目标文件同目录，确保同一文件系统）
/// 2. 写入数据到临时文件
/// 3. 同步到磁盘（fsync）
/// 4. 原子重命名临时文件为目标文件
///
/// ## 使用示例
/// ```swift
/// // 原子写入
/// let data = try JSONEncoder().encode(index)
/// try FileWriter.writeAtomically(data, to: indexURL)
///
/// // 追加写入
/// try FileWriter.append(embeddingData, to: embeddingsURL)
/// ```
enum FileWriter {

    /// 原子写入数据到文件
    ///
    /// 使用原子操作写入数据，确保写入过程不会被中断。
    /// 如果写入过程中应用崩溃，原文件不会被破坏。
    ///
    /// - Parameters:
    ///   - data: 待写入数据
    ///   - url: 目标文件 URL
    ///   - options: 写入选项，默认无
    /// - Throws: 文件写入错误
    static func writeAtomically(_ data: Data, to url: URL, options: Data.WritingOptions = []) throws {
        // 确保目标目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 创建临时文件名（与目标文件同目录，确保同一文件系统）
        let tempURL = directory.appendingPathComponent(".tmp_\(UUID().uuidString)")

        do {
            // 写入临时文件
            try data.write(to: tempURL, options: options.union(.atomic))

            // 同步到磁盘（确保数据持久化）
            try syncToDisk(tempURL)

            // 原子重命名
            try FileManager.default.moveItem(at: tempURL, to: url)

            Logger.index.debug("原子写入成功: \(url.lastPathComponent), size=\(data.count) bytes")
        } catch {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempURL)
            Logger.index.error("原子写入失败: \(url.lastPathComponent), error=\(error.localizedDescription)")
            throw error
        }
    }

    /// 追加数据到文件
    ///
    /// 高效追加数据到文件末尾，适用于日志、索引追加等场景。
    ///
    /// - Parameters:
    ///   - data: 待追加数据
    ///   - url: 目标文件 URL
    /// - Throws: 文件写入错误
    static func append(_ data: Data, to url: URL) throws {
        // 确保目标目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: url.path) {
            // 文件不存在，直接创建
            try data.write(to: url, options: .atomic)
            Logger.index.debug("创建文件并追加: \(url.lastPathComponent), size=\(data.count) bytes")
            return
        }

        // 获取文件句柄并追加
        let fileHandle = try FileHandle(forWritingTo: url)
        defer {
            do {
                try fileHandle.close()
            } catch {
                Logger.index.warning("关闭文件句柄失败: \(error.localizedDescription)")
            }
        }

        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)

        Logger.index.debug("追加写入成功: \(url.lastPathComponent), appended=\(data.count) bytes")
    }

    /// 同步文件到磁盘
    ///
    /// 调用 fsync 确保数据持久化到磁盘。
    /// 对于关键数据（如索引、检查点），应该同步以确保崩溃恢复。
    ///
    /// - Parameter url: 文件 URL
    /// - Throws: 同步错误
    static func syncToDisk(_ url: URL) throws {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.synchronize()
    }

    /// 安全删除文件
    ///
    /// 如果文件不存在，不会抛出错误。
    ///
    /// - Parameter url: 文件 URL
    static func safeRemove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.index.debug("删除文件成功: \(url.lastPathComponent)")
        } catch {
            // 文件不存在不算错误
            if !error.isFileNotFoundError {
                Logger.index.warning("删除文件失败: \(url.lastPathComponent), error=\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Error Extension

extension Error {
    /// 检查是否为"文件不存在"错误
    var isFileNotFoundError: Bool {
        (self as NSError).domain == NSCocoaErrorDomain &&
        (self as NSError).code == NSFileNoSuchFileError
    }
}
