# PhotoScanner AI 编码助手

> 本文件是 AI 编码助手的**核心操作手册**，聚焦原则而非规则。
>
> 详细背景知识见 `docs/context/`，架构设计见 `docs/context/ARCHITECTURE.md`，
> 开发工作流见 `docs/AI_WORKFLOW.md`，决策路由见 `docs/AI_ROUTING.md`。

## 工作模式

本项目采用**人类掌舵、Agent 执行**的协作模式：

- **人类**定义意图（做什么）、设计约束（不能做什么）、评估结果（做对了没有）
- **Agent**在约束边界内自主执行——读代码、分析问题、修改实现、验证构建
- **反馈**驱动收敛——修改后验证、验证后复审、复审后修正，直到问题消除

> Agent 遇到不确定的设计决策时，**停下来问人**，而不是凭推测行动。

## 核心原则（3条）

### 1. 四层架构原则

```
Foundation/       → 基础类型和配置（Embedding, Errors, Logger, 相似度计算）
Engine/           → 核心业务逻辑（索引构建、搜索执行、预处理）
Infrastructure/   → 技术基础设施（缓存、监控、ANE检测、调试工具）
Presentation/     → UI 展示（Views, ViewModels, Components）
Plugin/           → AI 模型插件（ChineseCLIP*）
```

**AI 推断**：目录名即职责，根据任务性质自然选择目标目录。

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
| 图片尺寸 | 256×256 | vImage 预处理 |
| Token 长度 | 72 | XLM-RoBERTa |
| Embedding 维度 | 768 | Chinese-CLIP |
| 搜索延迟 | ~45ms | P95 目标 |
| 最低 iOS | 26.0 | 无版本适配 |
| 最低设备 | iPhone 14 Pro | 无设备分级 |

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
2. **所有服务使用 actor 隔离**
3. **不要手动添加 @MainActor**
4. **依赖协议而非实现**
5. **仅支持真机构建**——本项目使用 `Photos` 等真机专属框架，不支持 iOS Simulator 构建
6. **核心链路注释日志不能偷懒**——每 Phase 完成后 commit

---

> 💡 **AI 提示**：Swift/SwiftUI 基础规范、标准库 API 使用等，AI 已内化，无需在此重复。
> 本文档聚焦项目特定的架构约定和易错点。
