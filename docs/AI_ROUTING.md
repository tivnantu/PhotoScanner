# AI 决策路由指南

> 🤖 本文件是 **AI 工具链组件**，供 Agent 按需读取。
>
> 职责：用户问题 → 快速定位相关文档/代码。不重复其他文件已定义的内容。

## 快速决策表

| 用户提问关键词 | 优先级读取 | 动作 |
|---------------|-----------|------|
| "Embedding是什么" | `context/GLOSSARY.md` | 提供语义解释 |
| "性能指标" | `context/QUICK_CONTEXT.md` | 提供基准数据 |
| "vDSP加速" | `Foundation/Math/SimdUtils.swift` | 查看实现 |
| "HNSW索引" | `Engine/Indexing/HNSWIndex.swift` | 查看实现 |
| "缓存策略" | `Infrastructure/Cache/` | 查看缓存实现 |
| "添加功能" | `AI_WORKFLOW.md` | 引导开发流程 |
| "报错/失败" | `context/EDGE_CASES.md` | 查找已知陷阱 |
| "架构" | `context/ARCHITECTURE.md` | 提供架构图 |
| "模型规格" | `context/MODEL_SPECS.md` | 技术规格 |
| "类型定义" | `Foundation/` | 值对象和配置 |
| "相似度计算" | `Foundation/SimilarityScore.swift` | 查看映射逻辑 |
| "快速了解" | `context/QUICK_CONTEXT.md` | 最小必要信息 |

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
  │   └── 内存相关 → Infrastructure/System/MemoryMonitor.swift
  │
  ├── 性能问题？
  │   ├── 搜索慢 → Infrastructure/Cache/
  │   ├── 索引慢 → Engine/Indexing/
  │   └── 内存高 → ResourceBudget.swift
  │
  └── 逻辑问题？
      ├── 搜索结果不准 → Engine/Search/
      └── 相似度异常 → SimilarityScore.swift
```

## 上下文窗口紧张时的读取顺序

```
优先级 1（必读，~2K tokens）:
  - context/QUICK_CONTEXT.md（最小必要信息）

优先级 2（按需，各 ~4-5K tokens）:
  - context/GLOSSARY.md（类型定义）
  - context/ARCHITECTURE.md（架构理解）

优先级 3（深入）:
  - context/MODEL_SPECS.md（模型规格）
  - 具体源代码文件
```

## 关联组件

- 功能开发路由 → 见 `AI_WORKFLOW.md`
- 系统知识 → `context/`
