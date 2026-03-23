import Foundation

/// 搜索历史管理器
actor SearchHistoryManager {
    static let shared = SearchHistoryManager()
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "SearchHistory"
    private let maxHistoryCount = 10
    
    private init() {}
    
    /// 获取搜索历史
    func getHistory() -> [String] {
        userDefaults.stringArray(forKey: historyKey) ?? []
    }
    
    /// 添加搜索历史
    func addHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var history = getHistory()
        
        // 移除重复项
        history.removeAll { $0 == trimmed }
        
        // 添加到开头
        history.insert(trimmed, at: 0)
        
        // 限制数量
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        
        userDefaults.set(history, forKey: historyKey)
    }
    
    /// 清除搜索历史
    func clearHistory() {
        userDefaults.removeObject(forKey: historyKey)
    }
    
    /// 删除单条历史
    func removeHistory(_ query: String) {
        var history = getHistory()
        history.removeAll { $0 == query }
        userDefaults.set(history, forKey: historyKey)
    }
}
