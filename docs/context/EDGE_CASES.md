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
struct MyView: View {
    var body: some View { ... }
}

// ✅ 正确（无需标注）
struct MyView: View {
    var body: some View { ... }
}
```

### Actor 跨边界回调

**问题**：跨 actor 边界的回调必须标注 @Sendable。

```swift
// ❌ 错误
actor MyService {
    func perform(callback: () -> Void) {  // callback 不是 Sendable
        Task { callback() }
    }
}

// ✅ 正确
actor MyService {
    func perform(callback: @Sendable () -> Void) {
        Task { callback() }
    }
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
// 使用 count 属性监控实际数量
```

### 图片内存峰值

**问题**：加载大图时内存峰值远超最终显示尺寸。

```swift
// ❌ 危险：直接加载原图
let image = UIImage(contentsOfFile: path)  // 可能 50MB+

// ✅ 安全：使用 ImageDownsampler 降采样
let thumbnail = await ImageDownsampler.downsample(
    url: url,
    maxDimension: 256
)  // 峰值可控
```

## 索引陷阱

### HNSW 参数不匹配

**问题**：构建和搜索使用不同的 ef 参数导致结果不一致。

```swift
// ❌ 错误
// 构建时 efConstruction = 200
// 搜索时 efSearch = 50  // 可能漏掉最近邻

// ✅ 正确
// efSearch 应该 >= efConstruction / 4
let config = HNSWConfig(
    efConstruction: 200,
    efSearch: 50  // OK: 200/4 = 50
)
```

### 检查点版本不兼容

**问题**：旧版本检查点可能导致崩溃。

```swift
// ✅ 解决：版本校验
guard (1...currentVersion).contains(checkpoint.version) else {
    try? fileManager.removeItem(at: checkpointURL)
    return nil
}
```

## 模型陷阱

### ANE 不支持

**问题**：某些旧设备不支持 ANE 加速。

```swift
// ✅ 解决：检测并降级
let checker = ANECompatibilityChecker()
let strategy = await checker.checkCompatibility()
if !strategy.supportsANE {
    // 使用 CPU 推理
}
```

### 模型文件 Git LFS

**问题**：克隆仓库时模型文件可能未下载。

```bash
# 检查
git lfs ls-files

# 下载
git lfs pull
```

## 构建陷阱

### 模拟器构建失败

**问题**：Photos 等框架不支持模拟器。

```bash
# ❌ 错误
xcodebuild -destination 'platform=iOS Simulator,name=iPhone 15'

# ✅ 正确
xcodebuild -destination 'platform=iOS,name=ta_iPhone14'
# 或无真机时
xcodebuild -destination 'generic/platform=iOS'
```

### Swift 6 严格并发

**问题**：Swift 6 默认启用严格并发检查。

```swift
// 常见错误：nonisolated 属性访问 isolated 存储
actor MyService {
    private var cache: [String: Data] = [:]
    
    // ❌ 错误
    nonisolated func get(_ key: String) -> Data? {
        cache[key]  // 访问 isolated 存储
    }
    
    // ✅ 正确
    func get(_ key: String) -> Data? {
        cache[key]
    }
}
```

## 缓存陷阱

### 缓存键冲突

**问题**：不同输入产生相同缓存键。

```swift
// ❌ 可能冲突
let key = "\(text)"  // 不同编码可能相同字符串

// ✅ 安全：使用哈希
let key = SHA256.hash(data: text.data(using: .utf8)!)
```

### 缓存过期

**问题**：源数据更新后缓存未失效。

```swift
// ✅ 解决：版本化缓存键
let cacheKey = "\(assetId)_v\(version)"
```
