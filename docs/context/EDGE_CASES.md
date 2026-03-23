# PhotoScanner 边缘案例

> 已知陷阱和边界场景，避免重复踩坑。

## 并发陷阱

### vDSP 原地操作

**问题**：vDSP 函数读写同一内存会导致数据损坏。

```swift
// ❌ 错误
vDSP_vsdiv(data, 1, &std, &data, 1, count)  // 读写同一 buffer

// ✅ 正确
var input = Array(data[0..<count])
var output = [Float](repeating: 0, count: count)
vDSP_vsdiv(input, 1, &std, &output, 1, count)
```

### View 手动标注 @MainActor

**问题**：SwiftUI View 自动隔离到 @MainActor，手动标注会导致警告。

```swift
// ❌ 错误
@MainActor
struct MyView: View { ... }

// ✅ 正确（无需标注）
struct MyView: View { ... }
```

### @unchecked Sendable 违规

**问题**：`HNSWIndex` 使用 `@unchecked Sendable`，违反项目红线。

```swift
// TODO: 评估改为 actor 或完全由 HNSWVectorStore 封装
final class HNSWIndex: @unchecked Sendable { ... }
```

### ThumbnailCache.preload 竞态

**问题**：`nonisolated` 方法创建 Task，高频调用可能产生竞态。

```swift
// TODO: 使用 Task.detached 或添加调用频率限制
nonisolated func preload(assetIds: [String]) {
    Task { await _preload(assetIds: assetIds) }
}
```

## 内存陷阱

### NSCache 计数 vs 限制

**问题**：`NSCache.totalCountLimit` 是建议值，不是硬限制。

```swift
// ❌ 错误假设
cache.totalCountLimit = 100
// 实际可能超过 100

// ✅ 正确理解
// totalCountLimit 是建议，系统可能忽略
```

### 图片内存峰值

**问题**：加载大图时内存峰值远超最终显示尺寸。

```swift
// ❌ 危险：直接加载原图
let image = UIImage(contentsOfFile: path)  // 可能 50MB+

// ✅ 安全：使用 ImageDownsampler
let thumbnail = await ImageDownsampler.downsample(
    url: url,
    maxDimension: 256
)
```

## 架构陷阱

### Foundation 层违规导入

**问题**：`PhotoLibraryAssetProvider` 位于 Foundation 层但导入了 UIKit/Photos。

```swift
// TODO: 移至 Infrastructure/ 层
import Photos
import UIKit
```

### Engine 层直接调用 FileManager

**问题**：`DiskBackedIndexStore` 和 `MMapBruteForceVectorStore` 直接调用 FileManager。

```swift
// TODO: 通过协议抽象文件操作
FileManager.default.fileExists(atPath: ...)
```

### 单例模式

**问题**：已修复。原 `SearchHistoryManager.shared` 违反依赖注入原则。

```swift
// ✅ 当前实现：构造器注入
init(userDefaults: UserDefaults = .standard)
```

## 模型陷阱

### 维度不匹配

**问题**：Chinese-CLIP ViT-B/16 输出 512 维，原 HNSW 默认配置为 768。

```swift
// ✅ 已修复
init(embeddingDimension: Int = 512)
```

### ANE 不支持

**问题**：某些旧设备不支持 ANE 加速。

```swift
let checker = ANECompatibilityChecker()
let strategy = await checker.checkCompatibility()
```

## 构建陷阱

### 模拟器构建失败

**问题**：Photos 等框架不支持模拟器。

```bash
# ❌ 错误
xcodebuild -destination 'platform=iOS Simulator'

# ✅ 正确
xcodebuild -destination 'platform=iOS,name=<真机>'
```

### 模型文件 Git LFS

**问题**：克隆仓库时模型文件可能未下载。

```bash
# 检查
git lfs ls-files

# 下载
git lfs pull
```

## 缓存陷阱

### 缓存键冲突

**问题**：不同输入产生相同缓存键。

```swift
// ❌ 可能冲突
let key = "\(text)"

// ✅ 安全：使用哈希
let key = SHA256.hash(data: text.data(using: .utf8)!)
```

### 缓存过期

**问题**：源数据更新后缓存未失效。

```swift
// ✅ 版本化缓存键
let cacheKey = "\(assetId)_v\(version)"
```
