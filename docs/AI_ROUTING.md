# AI 决策路由指南

> 🤖 AI 工具链组件：用户问题 → 快速定位相关文档/代码。

## 快速决策表

| 用户提问 | 优先读取 | 说明 |
|----------|----------|------|
| "Embedding是什么" | `context/GLOSSARY.md` | 核心概念定义 |
| "性能指标" | `context/QUICK_CONTEXT.md` | 基准数据速查 |
| "架构" | `context/ARCHITECTURE.md` | 五层架构与约束 |
| "模型规格" | `context/MODEL_SPECS.md` | Chinese-CLIP 参数 |
| "报错/失败" | `context/EDGE_CASES.md` | 已知陷阱 |
| "vDSP加速" | `Foundation/Math/SimdUtils.swift` | 实现代码 |
| "相似度计算" | `Foundation/SimilarityScore.swift` | 映射逻辑 |
| "添加功能" | `AI_WORKFLOW.md` | 开发流程 |

## 问题诊断流程

```
用户报告问题
  │
  ├── 编译错误？
  │   ├── Swift 6 并发错误 → 检查 actor 隔离
  │   └── 协议一致性错误 → 检查显式声明
  │
  ├── 运行时错误？
  │   ├── 索引相关 → EDGE_CASES.md + Engine/Indexing/
  │   ├── 搜索相关 → EDGE_CASES.md + Engine/Search/
  │   └── 内存相关 → Infrastructure/System/
  │
  ├── 性能问题？
  │   ├── 搜索慢 → SearchEngine + VectorStore
  │   ├── 索引慢 → IndexEngine + EmbeddingService
  │   └── 内存高 → ResourceBudget + Cache
  │
  └── 逻辑问题？
      ├── 搜索结果不准 → SimilarityScore / VectorStore
      └── 相似度异常 → EmbeddingService 归一化
```

## 上下文窗口紧张时的读取顺序

```
优先级 1（必读，~2K tokens）:
  - context/QUICK_CONTEXT.md

优先级 2（按需，各 ~3-5K tokens）:
  - context/GLOSSARY.md
  - context/ARCHITECTURE.md
  - context/EDGE_CASES.md

优先级 3（深入）:
  - context/MODEL_SPECS.md
  - 具体源代码文件
```

## 关键文件速查

| 功能 | 文件 |
|------|------|
| 模型推理 | `Plugin/ChineseCLIP/ChineseCLIPPlugin.swift` |
| Embedding门面 | `Engine/EmbeddingService.swift` |
| 向量检索 | `Engine/Indexing/MMapBruteForceVectorStore.swift` |
| 搜索编排 | `Engine/SearchEngine.swift` |
| 索引编排 | `Engine/Indexing/IndexEngine.swift` |
| 依赖注入 | `App/AppServices.swift` |
| 错误定义 | `Foundation/Errors.swift` |
| 日志分类 | `Foundation/Logger.swift` |

## 关联文档

- 功能开发流程 → `AI_WORKFLOW.md`
- 系统知识 → `context/`
