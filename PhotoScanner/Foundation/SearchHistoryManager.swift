import Foundation
import OSLog

/// 搜索历史项
struct SearchHistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let query: String
    let resultCount: Int
    let date: Date
    
    init(query: String, resultCount: Int = 0, date: Date = Date()) {
        self.id = UUID()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resultCount = resultCount
        self.date = date
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 搜索历史管理器
actor SearchHistoryManager {
    private let userDefaults: UserDefaults
    private let historyKey = "SearchHistory_v2"
    private let maxHistoryCount = 20
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    /// 获取搜索历史
    func getHistory() -> [SearchHistoryEntry] {
        guard let data = userDefaults.data(forKey: historyKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SearchHistoryEntry].self, from: data)
        } catch {
            Logger.app.warning("读取搜索历史失败: \(error)")
            return []
        }
    }
    
    /// 添加搜索历史
    func addHistory(_ query: String, resultCount: Int = 0) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var history = getHistory()
        
        // 移除重复项（相同查询）
        history.removeAll { $0.query == trimmed }
        
        // 创建新条目
        let entry = SearchHistoryEntry(query: trimmed, resultCount: resultCount)
        
        // 添加到开头
        history.insert(entry, at: 0)
        
        // 限制数量
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        
        // 保存
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            Logger.app.error("保存搜索历史失败: \(error)")
        }
    }
    
    /// 清除搜索历史
    func clearHistory() {
        userDefaults.removeObject(forKey: historyKey)
    }
    
    /// 删除单条历史
    func removeHistory(_ id: UUID) {
        var history = getHistory()
        history.removeAll { $0.id == id }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            Logger.app.error("删除搜索历史失败: \(error)")
        }
    }
}
