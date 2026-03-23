//
// IndexStore.swift
// PhotoScanner
//
// 索引存储边界。
// 当前阶段先定义协议，后续再决定磁盘、数据库或分片文件实现。
//

import Foundation

protocol IndexStore: Sendable {
    func loadSnapshot() async throws -> IndexSnapshot?
    func saveSnapshot(_ snapshot: IndexSnapshot) async throws
    func clear() async throws
}
