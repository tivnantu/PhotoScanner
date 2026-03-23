# PhotoScanner 术语表

> 系统中关键类型和概念的语义定义。

## 核心值对象

### Embedding

**位置**: `Foundation/Embedding.swift`

嵌入向量值对象，封装 Float 数组，提供：
- 余弦相似度计算（vDSP 加速）
- Codable 序列化
- Sendable 安全传递

```swift
struct Embedding: Sendable, Equatable, Codable {
    let data: [Float]  // 768 维
    let dimension: Int { data.count }
    
    func cosineSimilarity(to other: Embedding) -> Float
}
```

### SimilarityScore

**位置**: `Foundation/SimilarityScore.swift`

相似度分数值对象，封装 [0, 1] 范围的分数：
- 图文检索：高斜率 Sigmoid，放大差异
- 图图对比：温和刻度，直观展示

```swift
struct SimilarityScore: Sendable, Comparable {
    let value: Float  // [0, 1]
    
    static func from(cosine: Float, config: SimilarityConfig) -> SimilarityScore
    static func fromImageComparison(cosine: Float, config: SimilarityConfig) -> SimilarityScore
}
```

### SimilarityConfig

**位置**: `Foundation/SimilarityScore.swift`

相似度计算配置，包含 Sigmoid 映射参数：
- `logitScale`: 图文检索刻度（~98.86）
- `logitBias`: 图文检索偏置（~-10.0）
- `imageComparisonScale`: 图图对比刻度（~4.0）
- `imageComparisonBias`: 图图对比偏置（~1.5）

### ResourceBudget

**位置**: `Foundation/ResourceBudget.swift`

资源预算配置，定义各组件资源限制：
- 内存预算：Embedding 缓存 50MB + 缩略图 50MB + 模型 150MB
- 磁盘预算：Embedding 500MB + 索引 300MB
- 计算预算：并发索引 4 任务，热节流阈值 serious

## 索引相关

### HNSWIndex

**位置**: `Engine/Indexing/HNSWIndex.swift`

Hierarchical Navigable Small World 向量索引：
- O(log N) 搜索复杂度
- 参数：M=16, efConstruction=200, efSearch=50
- 使用 MinHeap/MaxHeap 进行候选管理

### IndexCheckpoint

**位置**: `Engine/Indexing/IndexCheckpoint.swift`

索引检查点，支持断点续传：
- `stage`: idle / building / ready / failed
- `candidateAssetIdentifiers`: 候选资源 ID
- `completedCount` / `totalCount`: 进度

### IndexCheckpointManager

**位置**: `Engine/Indexing/IndexCheckpointManager.swift`

检查点生命周期管理：
- 内存缓存
- 进度记录
- 完成清理

## 缓存相关

### EmbeddingCache

**位置**: `Infrastructure/Cache/EmbeddingCache.swift`

双级缓存（内存 + 磁盘）：
- 内存：NSCache，LRU 淘汰
- 磁盘：JSON 文件，SHA256 键
- 命中率 >90%

### ThumbnailCache

**位置**: `Infrastructure/Cache/ThumbnailCache.swift`

缩略图缓存：
- 内存：NSCache，500 张 / 50MB
- 并发预加载：最多 4 个并发请求

## 系统监控

### ThermalThrottler

**位置**: `Infrastructure/System/ThermalThrottler.swift`

设备热管理节流器：
- 监听 `ProcessInfo.thermalStateDidChangeNotification`
- 热状态达到 serious 时暂停后台任务

### MemoryMonitor

**位置**: `Infrastructure/System/MemoryMonitor.swift`

内存监控器：
- 监听 `UIApplication.didReceiveMemoryWarningNotification`
- 提供当前内存使用量查询

### ANECompatibilityChecker

**位置**: `Infrastructure/Performance/ANECompatibilityChecker.swift`

ANE（Apple Neural Engine）兼容性检测：
- 检测设备是否支持 ANE 加速
- 返回智能调度策略建议

## UI 组件

### ShimmerView

**位置**: `Presentation/Components/ShimmerView.swift`

骨架屏加载占位，平滑动画。

### ZoomableImageViewer

**位置**: `Presentation/Components/ZoomableImageViewer.swift`

可缩放图片查看器：
- 双指缩放（1x ~ 3x）
- 拖拽平移
- 双击切换
- 下滑关闭

### PerformanceOverlay

**位置**: `Presentation/Components/PerformanceOverlay.swift`

浮动性能监控面板（DEBUG only）：
- 内存、温度、FPS
- 可拖拽、可折叠

### HapticFeedback

**位置**: `Presentation/Design/HapticFeedback.swift`

触感反馈工具：
- `success()` / `warning()` / `error()`
- `selection()`
- `forScore(_:)` 根据分数自动选择

## 错误类型

### PSError

**位置**: `Foundation/Errors.swift`

项目错误枚举：
- `modelNotLoaded` - 模型未加载
- `searchFailed` - 搜索失败
- `indexBuildFailed` - 索引构建失败
- `invalidImage` - 无效图片
- `imageResizeFailed` - 图片缩放失败
- `storageCorrupted` - 存储损坏
