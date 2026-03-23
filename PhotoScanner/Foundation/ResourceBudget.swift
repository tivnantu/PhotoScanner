import Foundation

// MARK: - ResourceBudget

/// 资源预算
///
/// 定义各组件的资源使用限制，用于内存管理和性能调优。
/// 
/// ## 设计背景
/// iOS 设备资源有限，需要对各组件设置预算上限：
/// - 内存预算防止 OOM 崩溃
/// - 磁盘预算控制存储空间
/// - 计算预算优化并发策略
///
/// ## 使用示例
/// ```swift
/// let budget = ResourceBudget()
/// print(budget.memory.total)  // 260 MB
/// print(budget.compute.maxConcurrentIndexing)  // 4
/// ```
struct ResourceBudget: Codable, Sendable {
    
    // MARK: - 内存预算
    
    /// 内存预算配置
    struct MemoryBudget: Codable, Sendable {
        /// Embedding 缓存（50 MB）
        /// - Note: 每个 Embedding 约 2KB，可缓存 25,000 个
        let embeddingCache: Int64
        
        /// 文本缓存（10 MB）
        /// - Note: 缓存 OCR 文本和分词结果
        let textCache: Int64
        
        /// 图像数据缓存（50 MB）
        /// - Note: 缩略图和预处理中间数据
        let imageData: Int64
        
        /// 索引数据（100 MB）
        /// - Note: mmap 映射，不计入实际内存
        let indexData: Int64
        
        /// 模型占用（150 MB）
        /// - Note: Chinese-CLIP 模型内存占用
        let models: Int64
        
        /// 总预算（不含 mmap）
        var total: Int64 {
            embeddingCache + textCache + imageData + models
        }
        
        /// 默认初始化器
        init(
            embeddingCache: Int64 = 50 * 1024 * 1024,
            textCache: Int64 = 10 * 1024 * 1024,
            imageData: Int64 = 50 * 1024 * 1024,
            indexData: Int64 = 100 * 1024 * 1024,
            models: Int64 = 150 * 1024 * 1024
        ) {
            self.embeddingCache = embeddingCache
            self.textCache = textCache
            self.imageData = imageData
            self.indexData = indexData
            self.models = models
        }
        
        /// 各组件占比
        var breakdown: [String: Int64] {
            [
                "Embedding Cache": embeddingCache,
                "Text Cache": textCache,
                "Image Data": imageData,
                "Index Data (mmap)": indexData,
                "Models": models
            ]
        }
    }
    
    // MARK: - 磁盘预算
    
    /// 磁盘预算配置
    struct DiskBudget: Codable, Sendable {
        /// Embedding 存储（500 MB）
        let embeddings: Int64
        
        /// OCR 索引（200 MB）
        let ocrIndex: Int64
        
        /// Scene 索引（100 MB）
        let sceneIndex: Int64
        
        /// 缓存目录（100 MB）
        let cache: Int64
        
        /// 日志（50 MB）
        let logs: Int64
        
        /// 总预算
        var total: Int64 {
            embeddings + ocrIndex + sceneIndex + cache + logs
        }
        
        /// 默认初始化器
        init(
            embeddings: Int64 = 500 * 1024 * 1024,
            ocrIndex: Int64 = 200 * 1024 * 1024,
            sceneIndex: Int64 = 100 * 1024 * 1024,
            cache: Int64 = 100 * 1024 * 1024,
            logs: Int64 = 50 * 1024 * 1024
        ) {
            self.embeddings = embeddings
            self.ocrIndex = ocrIndex
            self.sceneIndex = sceneIndex
            self.cache = cache
            self.logs = logs
        }
    }
    
    // MARK: - 计算预算

    /// 计算预算配置
    struct ComputeBudget: Sendable, Codable {
        /// 最大并发索引任务
        /// - Note: 避免过多并发导致内存压力
        let maxConcurrentIndexing: Int

        /// 最大并发搜索任务
        /// - Note: 搜索计算密集，限制并发
        let maxConcurrentSearch: Int

        /// 后台任务超时（秒）
        let backgroundTaskTimeout: TimeInterval

        /// 热节流阈值 (存储为 Int rawValue)
        /// - Note: 达到此温度时暂停后台任务
        let thermalThrottleThresholdRaw: Int

        /// 热节流阈值（计算属性）
        var thermalThrottleThreshold: ProcessInfo.ThermalState {
            ProcessInfo.ThermalState(rawValue: thermalThrottleThresholdRaw) ?? .nominal
        }
        
        /// 默认初始化器
        init(
            maxConcurrentIndexing: Int = 4,
            maxConcurrentSearch: Int = 2,
            backgroundTaskTimeout: TimeInterval = 180,
            thermalThrottleThreshold: ProcessInfo.ThermalState = .serious
        ) {
            self.maxConcurrentIndexing = maxConcurrentIndexing
            self.maxConcurrentSearch = maxConcurrentSearch
            self.backgroundTaskTimeout = backgroundTaskTimeout
            self.thermalThrottleThresholdRaw = thermalThrottleThreshold.rawValue
        }
    }
    
    // MARK: - 属性
    
    /// 内存预算
    let memory: MemoryBudget
    
    /// 磁盘预算
    let disk: DiskBudget
    
    /// 计算预算
    let compute: ComputeBudget
    
    /// 默认配置
    init(
        memory: MemoryBudget = .init(),
        disk: DiskBudget = .init(),
        compute: ComputeBudget = .init()
    ) {
        self.memory = memory
        self.disk = disk
        self.compute = compute
    }
}

// MARK: - 调试信息

extension ResourceBudget: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        ResourceBudget:
          Memory:
            - Total: \(memory.total / 1024 / 1024) MB
            - Breakdown: \(memory.breakdown.mapValues { "\($0 / 1024 / 1024) MB" })
          Disk:
            - Total: \(disk.total / 1024 / 1024) MB
          Compute:
            - Max concurrent indexing: \(compute.maxConcurrentIndexing)
            - Thermal threshold: \(compute.thermalThrottleThreshold)
        """
    }
}
