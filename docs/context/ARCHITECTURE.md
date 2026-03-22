# 架构设计

> 本文档记录 PhotoScanner 的工程分层、依赖规则和核心数据链路。

## 分层结构

```
Presentation ──► Engine ──► Plugin ──► Foundation
```

依赖严格单向，不允许反向引用。

| 层 | 目录 | 职责 | 关键约束 |
|----|------|------|---------|
| **Foundation** | `Foundation/` | 错误定义、日志、资源定位 | 不依赖任何上层 |
| **Plugin** | `Plugin/` | 模型推理实现、预处理、tokenizer | ONNX Runtime 只在这一层出现 |
| **Engine** | `Engine/` | 业务门面：embedding、相似度 | 只依赖 `ModelPlugin` 协议，不知道底层实现 |
| **Presentation** | `Presentation/` | UI 视图、ViewModel | 只依赖 Engine |
| **App** | `App/` | Composition Root、Environment 注入 | 唯一允许跨层"接线"的地方 |

## 文件索引

```
PhotoScanner/
├── App/
│   ├── AppServices.swift                    # 服务引用聚合
│   └── Environment+Services.swift           # EnvironmentKey 注入
├── Foundation/
│   ├── Errors.swift                         # PSError 统一错误枚举
│   ├── Logger.swift                         # OSLog 按模块分类
│   └── BundleResource.swift                 # Bundle 资源定位
├── Plugin/
│   ├── ModelPlugin.swift                    # ★ 核心协议
│   ├── EmptyModelPlugin.swift               # Fallback / Preview
│   └── ChineseCLIP/
│       ├── ChineseCLIPPlugin.swift          # ONNX 双塔实现
│       ├── ChineseCLIPTokenizer.swift       # Bert WordPiece tokenizer
│       └── ChineseCLIPImagePreprocessor.swift # 图像 Resize + Normalize
├── Engine/
│   ├── EmbeddingService.swift               # embedding 统一门面 (actor)
│   └── SimilarityEngine.swift               # 图文相似度计算 (Sendable class)
├── Presentation/
│   └── SimilarityDebug/
│       ├── SimilarityDebugView.swift        # 验证页 UI
│       └── SimilarityDebugViewModel.swift   # 验证页状态
├── ContentView.swift                        # 首页路由
└── PhotoScannerApp.swift                    # Composition Root
```

## 核心协议

`ModelPlugin` 是连接 Engine 和 Plugin 的唯一桥梁：

```swift
protocol ModelPlugin: Sendable {
    var descriptor: ModelDescriptor { get }
    func load() async throws
    func unload() async
    func encodeImage(_ imageData: Data) async throws -> [Float]
    func encodeText(_ text: String) async throws -> [Float]
}
```

**设计要点**：
- 接口只接收原始数据（`Data` / `String`），预处理在实现内部完成
- 输出为**未归一化**的 embedding，L2 归一化由 `EmbeddingService` 统一处理
- 所有模型常量（mean / std / context_length）封装在具体实现内部，不向外泄露

## 并发模型

| 类型 | 隔离方式 | 理由 |
|------|---------|------|
| `ChineseCLIPPlugin` | actor | 持有 ORT Session 等可变状态 |
| `EmbeddingService` | actor | 持有 plugin 引用 + isReady 状态 |
| `SimilarityEngine` | Sendable class | 无可变状态，纯编排（调用 EmbeddingService） |
| `SimilarityDebugViewModel` | @Observable @MainActor | UI 状态，主线程隔离 |

## 依赖注入

采用 **Composition Root + EnvironmentKey** 模式：

1. `PhotoScannerApp.init()` 组装 Plugin → Engine → Services
2. `AppServices` 是纯引用聚合（struct），不含业务逻辑
3. 通过 `.environment(\.services, services)` 注入视图树
4. 下游通过 `@Environment(\.services)` 消费

不使用 ServiceContainer / 全局单例。

## 第一阶段数据链路

当前唯一目标：**1 张图 + 1 条文本 → 1 个相似度分数**。

```
用户选图                    用户输入文本
  │ (Data)                    │ (String)
  ▼                           ▼
┌─────────────────────────────────────────┐  Presentation
│        SimilarityDebugViewModel         │
└──────────────┬──────────────┬───────────┘
               │              │
               ▼              ▼
┌─────────────────────────────────────────┐  Engine
│          SimilarityEngine               │
│  imageEmb = embeddingService.embedImage │
│  textEmb  = embeddingService.embedText  │
│  score    = dot(imageEmb, textEmb)      │
└──────────────┬──────────────┬───────────┘
               │              │
               ▼              ▼
┌─────────────────────────────────────────┐  Engine
│          EmbeddingService               │
│  raw = plugin.encodeImage / encodeText  │
│  return L2Normalize(raw)                │
└──────────────┬──────────────┬───────────┘
               │              │
               ▼              ▼
┌──────────────────────┐ ┌────────────────┐  Plugin
│  ChineseCLIPPlugin   │ │ ChineseCLIPPlugin│
│  图像链路:            │ │ 文本链路:        │
│  Data → CGImage      │ │ String          │
│  → Resize 224 Bicubic│ │ → BasicTokenize │
│  → RGB Float [0,1]   │ │ → WordPiece     │
│  → HWC → CHW         │ │ → [CLS]+ids+[SEP]+[PAD]│
│  → Normalize(mean,std)│ │ → [52] int64   │
│  → ORT Session       │ │ → ORT Session   │
│  → [512] float       │ │ → [512] float   │
└──────────────────────┘ └────────────────┘
```

## 演进方向

第一阶段骨架天然支撑后续扩展，不需要破坏已有代码：

| 后续能力 | 扩展方式 |
|----------|---------|
| 批量索引 | Engine 层新增 `IndexEngine`，复用 `EmbeddingService` |
| 文搜图 / 图搜图 | Engine 层新增 `SearchEngine`，依赖 `VectorStore` |
| 模型替换（CoreML / 其他模型） | Plugin 层新增实现，Composition Root 切换注入 |
| 聚类 | Engine 层新增 `ClusterEngine` |
| 完整产品 UI | Presentation 层新增页面，Engine 接口不变 |
