# PhotoScanner 文档索引

> 五层文档体系：README → AGENTS → context → topics → 代码

## 文档层级

| 层级 | 位置 | 内容 | 读者 |
|------|------|------|------|
| 1 - 项目简介 | `README.md` | 项目是什么、特性、快速开始 | 外部用户 |
| 2 - AI 协作 | `AGENTS.md` | 编码原则、快速导航 | AI 助手 |
| 3 - 系统知识 | `docs/context/` | 系统现状（稳定事实）| 开发者 |
| 4 - 开发活动 | `docs/topics/` | 演进历史、专项讨论 | 维护者 |
| 5 - 实现 | `代码 + 注释` | 真实系统状态 | 全员 |

## 快速入口

### 第一次接触？
1. [`context/QUICK_CONTEXT.md`](context/QUICK_CONTEXT.md) - 最小必要信息
2. [`context/ARCHITECTURE.md`](context/ARCHITECTURE.md) - 架构设计

### 开发工作
- [`AI_WORKFLOW.md`](AI_WORKFLOW.md) - 开发流程指南
- [`AI_ROUTING.md`](AI_ROUTING.md) - 问题诊断路由

### 系统知识（context/）

| 文档 | 内容 | 何时阅读 |
|------|------|----------|
| [`QUICK_CONTEXT.md`](context/QUICK_CONTEXT.md) | 关键参数、性能指标 | 日常速查 |
| [`ARCHITECTURE.md`](context/ARCHITECTURE.md) | 五层架构、依赖规则、数据链路 | 架构理解 |
| [`GLOSSARY.md`](context/GLOSSARY.md) | 核心类型与概念 | 术语查询 |
| [`MODEL_SPECS.md`](context/MODEL_SPECS.md) | Chinese-CLIP 技术参数 | 模型相关 |
| [`EDGE_CASES.md`](context/EDGE_CASES.md) | 已知陷阱与边界 | 问题排查 |
| [`BASELINE_TESTS.md`](context/BASELINE_TESTS.md) | 回归测试说明 | 测试相关 |

## 维护原则

- **context/** 只放稳定知识，代码变更后立即同步
- **topics/** 记录历史，只追加不删除
- 同一信息只维护一份（SSOT）
- 复杂图表使用 Mermaid 语法

## 关联文件

- 项目根目录 [`AGENTS.md`](../AGENTS.md) - AI 编码助手操作手册
- 项目根目录 [`README.md`](../README.md) - 项目对外简介
