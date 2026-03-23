# AI 开发工作流

> 🔄 AI 工具链组件：功能开发 / Bug 修复 / 重构的实施流程。

## 架构分层

```
├── Foundation/          # 基础类型（纯 Swift，零外部依赖）
│   ├── Embedding.swift
│   ├── SimilarityScore.swift
│   ├── ResourceBudget.swift
│   ├── Errors.swift
│   ├── Logger.swift
│   └── Math/SimdUtils.swift
│
├── Engine/              # 核心业务逻辑
│   ├── EmbeddingService.swift
│   ├── SimilarityEngine.swift
│   ├── SearchEngine.swift
│   └── Indexing/        # 索引构建
│
├── Infrastructure/      # 技术基础设施
│   ├── Cache/           # EmbeddingCache, ThumbnailCache
│   ├── System/          # ThermalThrottler, MemoryMonitor
│   └── Performance/     # RuntimePerformanceStore
│
├── Presentation/        # UI 层
│   └── TextSearch/      # 主功能入口
│
├── Plugin/              # AI 模型插件
│   └── ChineseCLIP/
│
└── App/                 # Composition Root
    ├── AppServices.swift
    └── PhotoScannerApp.swift
```

### 架构红线（不可违反）

1. **Foundation 层**：禁止 import `UIKit`、`Photos`、`CoreML`、`ONNX`
2. **Engine 层**：禁止直接调用 `FileManager`、`PHAsset.fetchAssets`
3. **Presentation 层**：禁止执行文件 I/O 或网络操作
4. **所有层**：禁止新增 `.shared` 单例，必须构造器注入

## 新功能开发流程

### Step 1: 需求分析

判断功能类型：

```
├── 搜索相关？ → Engine/Search/
├── 索引相关？ → Engine/Indexing/
├── UI相关？   → Presentation/
├── 性能相关？ → Infrastructure/Cache/
└── 模型相关？ → Plugin/
```

### Step 2: Foundation 层（如需要）

```swift
// 新数据类型
struct NewType: Sendable, Equatable, Codable {
    let data: [Float]
}

// 新错误类型
enum PSError {
    case newError(String)
}

// 新日志分类
extension Logger {
    static let newCategory = Logger(subsystem: subsystem, category: "new")
}
```

### Step 3: Engine 层

```swift
actor NewService: Sendable {
    // 依赖注入
    private let dependency: SomeDependency
    
    init(dependency: SomeDependency) {
        self.dependency = dependency
    }
    
    // 业务方法
    func perform(input: Input) async throws -> Output {
        Logger.newCategory.info("开始执行...")
        // ...
    }
}
```

### Step 4: Infrastructure 层（如需要）

- 缓存 → `Infrastructure/Cache/`
- 监控 → `Infrastructure/System/`
- 性能 → `Infrastructure/Performance/`

### Step 5: UI 层（如需要）

```swift
@Observable
@MainActor
class FeatureViewModel {
    private let services: AppServices
    
    init(services: AppServices) {
        self.services = services
    }
}
```

### Step 6: 依赖注入

在 `PhotoScannerApp.swift` 中组装：

```swift
let newService = NewService(dependency: ...)
services = AppServices(
    // ... 现有服务
    newService: newService
)
```

## Bug 修复流程

```
1. 复现问题
2. 定位层级（Foundation/Engine/Infrastructure/Presentation）
3. 检查 EDGE_CASES.md 是否已知问题
4. 修复代码
5. 验证构建通过
6. 更新相关文档（架构变更需更新 ARCHITECTURE.md）
```

## 重构流程

```
触发条件：
- 代码重复
- 职责不清
- 性能瓶颈

步骤：
1. 确保有测试覆盖
2. 小步重构，频繁验证
3. 更新 ARCHITECTURE.md（如架构变更）
```

## 代码审查清单

```
□ 遵循五层架构，无反向依赖
□ 可变状态使用 actor 隔离
□ 无 force unwrap / try! / as!
□ 日志使用分类 Logger.{category}
□ 错误使用 PSError 枚举
□ 依赖通过构造器注入（无 .shared 单例）
□ 核心链路有日志记录
```

## 文档同步规则

| 变更类型 | 需更新文档 |
|----------|-----------|
| 架构调整 | `context/ARCHITECTURE.md` |
| 新增类型 | `context/GLOSSARY.md` |
| 模型相关 | `context/MODEL_SPECS.md` |
| 性能参数 | `context/QUICK_CONTEXT.md` |
| 已知陷阱 | `context/EDGE_CASES.md` |
