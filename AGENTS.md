# PhotoScanner AI 编码助手

> 本文件是 AI 编码助手的**核心操作手册**，聚焦原则而非规则。
>
> 详细背景知识见 `docs/context/`，架构设计见 `docs/context/ARCHITECTURE.md`，
> 开发工作流见 `docs/AI_WORKFLOW.md`，决策路由见 `docs/AI_ROUTING.md`。

## 工作模式

**人类掌舵、Agent 执行**：

- **人类**定义意图（做什么）、设计约束（不能做什么）、评估结果
- **Agent**在约束边界内自主执行——读代码、分析问题、修改实现、验证构建
- **反馈**驱动收敛——修改后验证、验证后复审、复审后修正

> Agent 遇到不确定的设计决策时，**停下来问人**，而不是凭推测行动。

## 核心原则（3条）

### 1. 五层架构原则

```
Foundation/       → 基础类型和配置（纯 Swift，零外部依赖）
Engine/           → 核心业务逻辑（索引构建、搜索执行）
Infrastructure/   → 技术基础设施（缓存、监控、调试工具）
Presentation/     → UI 展示（Views, ViewModels）
Plugin/           → AI 模型插件（ChineseCLIP*）
```

**架构红线**（不可违反）：

1. **Foundation 层**：禁止 import `UIKit`、`Photos`、`CoreLocation`、`Vision`、`CoreML`、`ONNX`
2. **Engine 层**：禁止直接调用 `FileManager`、`PHAsset.fetchAssets` 等基础设施 API
3. **Presentation 层**：禁止执行文件 I/O 或网络操作
4. **所有层**：禁止新增 `.shared` 单例，必须通过构造器注入协议

### 2. Swift 6 并发原则

- **可变状态** → `actor` 隔离
- **纯计算** → `nonisolated`
- **Views** → 自动 `@MainActor`，**不手动标注**
- **跨 Actor 调用** → 必须 `await`

**⚠️ 易错点**：
```swift
// ❌ 禁止：vDSP 原地操作（读写同一内存）
vDSP_vsdiv(data, 1, &std, &data, 1, count)

// ✅ 正确：独立输入/输出缓冲区
var input = Array(data[0..<count])
var output = [Float](repeating: 0, count: count)
vDSP_vsdiv(input, 1, &std, &output, 1, count)
```

### 3. 依赖注入原则

- **构造器注入**：所有依赖通过构造器传入协议
- **禁止**：直接使用 `.shared` 单例

```swift
// ✅ 正确
actor SearchEngine: Sendable {
    init(store: any IndexStore, cache: any EmbeddingCache) {}
}

// ❌ 错误
let store = DiskBackedIndexStore.shared
```

## 快速导航

| 要做什么 | 读取文档 |
|---------|---------|
| 理解类型定义 | `Foundation/` + `docs/context/GLOSSARY.md` |
| 理解架构 | `docs/context/ARCHITECTURE.md` |
| 添加功能 | `docs/AI_WORKFLOW.md` |
| 故障排查 | `docs/context/EDGE_CASES.md` |
| 路由决策 | `docs/AI_ROUTING.md` |

## 关键参数速查

> 权威源：`docs/context/QUICK_CONTEXT.md`

| 参数 | 值 | 说明 |
|------|-----|------|
| 图片尺寸 | 224×224 | 模型输入尺寸 |
| Token 长度 | 52 | 含 [CLS]/[SEP] |
| Embedding 维度 | **512** | Chinese-CLIP ViT-B/16 |
| 搜索延迟 | ~45ms | P95 目标 |
| 最低 iOS | 26.0 | Swift 6 严格并发 |
| 最低设备 | iPhone 14 Pro | ANE 加速 |

## 日志分类速查

```swift
Logger.app      // 应用生命周期、启动、初始化
Logger.model    // 模型加载、推理、预处理
Logger.search   // 搜索、相似度计算
Logger.index    // 索引构建、维护
Logger.vision   // 图片预处理、降采样、缓存
Logger.ui       // UI 交互、导航
Logger.system   // 系统、崩溃处理
```

## 注意事项

1. **模型文件使用 Git LFS**
2. **所有服务使用 actor 隔离可变状态**
3. **不要手动添加 @MainActor 到 View**
4. **依赖协议而非实现**
5. **仅支持真机构建**——使用 Photos 框架，不支持 iOS Simulator
6. **核心链路日志不能偷懒**——关键路径必须有日志记录

---

> 💡 **AI 提示**：Swift/SwiftUI 基础规范 AI 已内化，本文档聚焦项目特定的架构约定和易错点。
