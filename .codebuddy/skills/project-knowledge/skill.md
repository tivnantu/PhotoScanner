---
name: project-knowledge
description: PhotoScanner 项目速查知识库。提供架构原则、关键约束和源码导航，引导 Agent 从代码中动态获取具体细节。
---

# PhotoScanner 项目知识库

> 只编码**稳定的架构原则和约束**，具体参数/类型/数据流由 Agent 读源码动态获取。
>
> **数据源声明**：本 skill 是以下权威源的精简摘要，修改源文件后需同步更新：
> - 项目定位/源码导航 → `docs/context/QUICK_CONTEXT.md`
> - 编码原则/红线 → `AGENTS.md` + `rules/code-quality-standards.mdc`
> - 文档导航 → `docs/context/README.md`
>
> **与 rules 的关系**：`rules/code-quality-standards.mdc` 已自动注入每次对话，
> 本 skill 补充 rules 未覆盖的**导航和上下文**，不重复红线条目。

## 项目定位

iOS 本地相册语义搜索 App。用户输入自然语言，返回匹配的照片。
核心能力：文搜图 | 图搜图 | 图文相似度计算

## 五层架构

```
Foundation/       → 基础类型和配置（Embedding, Errors, Logger, 相似度计算）
Engine/           → 核心业务逻辑（索引构建、搜索执行、预处理）
Infrastructure/   → 技术基础设施（缓存、监控、ANE检测、调试工具）
Presentation/     → UI 展示（Views, ViewModels, Components）
Plugin/           → AI 模型插件（ChineseCLIP*）
```

依赖方向：Presentation → Engine → Foundation ← Infrastructure ← Plugin

**红线**：Foundation 层禁止 import UIKit/Photos/CoreLocation/Vision/CoreML/ONNX

## 核心约束（稳定）

- Swift 6 strict concurrency：可变状态 → actor，纯计算 → nonisolated，View 不手动标 @MainActor
- 依赖注入：构造器注入协议，禁止 .shared 单例
- vDSP 禁止原地操作（输入输出必须是独立缓冲区）
- 性能预算：搜索 P95 ≤ 45ms，预处理 ≤ 5ms/张
- 仅支持真机构建（使用 Photos 等真机专属框架）

## 源码导航

需要了解具体细节时，直接读源文件——比任何文档都准确：

| 要了解什么 | 读哪里 |
|-----------|--------|
| 基础类型定义 | `Foundation/` |
| 搜索数据流 | `Engine/SearchEngine.swift` 入口向下追踪 |
| 索引构建 | `Engine/Indexing/IndexEngine.swift` 入口向下追踪 |
| 模型插件 | `Plugin/ChineseCLIP/` |
| 缓存实现 | `Infrastructure/Cache/` |
| 性能监控 | `Infrastructure/Performance/` |
| UI 组件 | `Presentation/` |
| 编码规范 | `AGENTS.md` |

## 五层级文档导航

项目知识分布在五个层级，根据需要按需读取——不要一次全读：

| 层级 | 路径 | 定位 | 何时读 |
|------|------|------|--------|
| 项目简介 | `README.md` | 对外概览 | 首次接触项目、需要项目定位 |
| 编码规范 | `AGENTS.md` | AI 操作手册 | 写代码前确认约束 |
| 系统现状 | `docs/context/` | 当前架构快照 | 理解系统设计、修改前确认边界 |
| 开发历史 | `docs/topics/` | 做了什么、为什么 | 遇到不理解的设计决策 |
| 代码 | 源文件 | 最权威的事实 | 需要具体实现细节 |

### docs/context/ — 系统现状（按需读取）

| 文档 | 内容 | 适合场景 |
|------|------|---------|
| `QUICK_CONTEXT.md` | 最小必要信息 | 快速了解项目全貌 |
| `ARCHITECTURE.md` | 模块边界、依赖关系 | 架构分析、跨模块修改 |
| `DATA_FLOW.md` | 从输入到输出的完整流程 | 搜索/索引相关开发 |
| `GLOSSARY.md` | 类型定义、命名约定 | 新增类型、理解领域概念 |
| `AI_ROUTING.md` | 决策路由 | 不确定如何处理某任务时 |
| `AI_WORKFLOW.md` | 开发工作流 | 功能开发流程 |
| `EDGE_CASES.md` | 异常处理、已知陷阱 | 修改边界逻辑前、排查异常 |

### docs/topics/ — 开发历史（按专项读取）

| 专项 | 路径 | 适合场景 |
|------|------|---------|
| 性能优化 | `docs/topics/performance/` | 理解为什么选择某算法/数据结构 |
| 准确度优化 | `docs/topics/accuracy/` | 理解排序/召回策略演进 |
| 功能开发 | `docs/topics/features/` | 理解功能设计决策 |
| 工程化 | `docs/topics/engineering/` | 理解架构/并发/DI 演进 |
| UI 设计 | `docs/topics/ui/` | 理解设计系统/交互决策 |

每个专项目录下都有 `README.md`（导航）和 `00-overview.md`（概览），从这两个文件开始。
