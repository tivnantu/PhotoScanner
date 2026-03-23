# PhotoScanner 术语表

> 系统中关键类型和概念的语义定义。

## 核心值对象

### Embedding

**位置**: `Foundation/Embedding.swift`

嵌入向量值对象，封装 Float 数组：

```swift
struct Embedding: Sendable, Equatable, Codable {
    let data: [Float]  // 512 维 (Chinese-CLIP ViT-B/16)
    
    func cosineSimilarity(to other: Embedding) -> Float
}
```

### SimilarityScore

**位置**: `Foundation/SimilarityScore.swift`

相似度分数值对象，范围 [0, 1]：

- 图文检索：高斜率 Sigmoid，放大差异便于排序
- 图图对比：温和刻度，直观展示

### ResourceBudget

**位置**: `Foundation/ResourceBudget.swift`

资源预算配置：
- 内存：Embedding 50MB + 缩略图 50MB + 模型 150MB
- 磁盘：Embedding 500MB + 索引 300MB
- 并发：4 任务，热节流阈值 serious

## 索引相关

### IndexSnapshot

**位置**: `Engine/Indexing/IndexSnapshot.swift`

索引快照，包含：
- `manifest`: 索引元数据（模型版本、维度、条目数）
- `entries`:  embedding 记录数组

### VectorStore

**位置**: `Engine/Indexing/VectorStore.swift`

向量检索协议：

```swift
protocol VectorStore: Sendable {
    func search(queryEmbedding: [Float], topK: Int) async throws -> [VectorSearchResult]
    func replaceSnapshot(_ snapshot: IndexSnapshot) async throws
}
```

当前实现：
- `MMapBruteForceVectorStore` — 主实现，mmap + Float32
- `BruteForceVectorStore` — 内存版基线
- `HNSWVectorStore` — HNSW 近似检索（备用）

### IndexEngine / SearchEngine

| 引擎 | 职责 |
|------|------|
| `IndexEngine` | 图片 → embedding → 索引落盘 |
| `SearchEngine` | 文本 → query embedding → 向量检索 |

## 缓存相关

### EmbeddingCache

**位置**: `Infrastructure/Cache/EmbeddingCache.swift`

双级缓存（内存 + 磁盘），命中率 >90%。

### ThumbnailCache

**位置**: `Infrastructure/Cache/ThumbnailCache.swift`

缩略图缓存：
- 内存：NSCache，500 张 / 50MB
- 并发预加载：最多 4 个并发请求

## 模型相关

### ModelPlugin

**位置**: `Plugin/ModelPlugin.swift`

模型插件协议，连接 Engine 和 Plugin 层。

### ChineseCLIPPlugin

**位置**: `Plugin/ChineseCLIP/ChineseCLIPPlugin.swift`

Chinese-CLIP ViT-B/16 的 ONNX Runtime 实现。

**关键参数**:
- embedding 维度: 512
- 图像尺寸: 224×224
- Token 长度: 52

## 系统监控

### ThermalThrottler

**位置**: `Infrastructure/System/ThermalThrottler.swift`

设备热管理节流器，热状态达到 serious 时暂停后台任务。

### MemoryMonitor

**位置**: `Infrastructure/System/MemoryMonitor.swift`

内存监控器，接收系统内存警告通知。

## 错误类型

### PSError

**位置**: `Foundation/PSError.swift`

项目错误枚举：
- `modelNotLoaded` — 模型未加载
- `searchFailed` — 搜索失败
- `indexBuildFailed` — 索引构建失败
- `storageCorrupted` — 存储损坏
