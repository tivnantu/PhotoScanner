---
name: engineering-workflow
description: 工程专项执行方法论。提供规划模板、编排流程、分批策略和进度追踪模式。当主 Agent 需要启动、规划或执行工程专项时加载。
---

# 工程专项执行方法论

> 供主 Agent（编排器）使用的通用工程专项执行框架。
> 不是给子 Agent 用的——子 Agent 由主 Agent 调度。

## 专项执行五步法

```
Step 1: 现状分析（用 analyzer 子 Agent）
Step 2: 规划拆解（主 Agent 自己做）
Step 3: 分批执行（用 fixer 子 Agent）
Step 4: 验证确认（构建 + 可选复审）
Step 5: 记录沉淀（更新 docs/）
```

## Step 1: 现状分析

### 前置文档阅读

分发 analyzer 前，主 Agent 自己先读取背景文档（按分析类型选读）：

| 专项类型 | 建议先读 | 目的 |
|---------|---------|---------|
| 代码质量 | `docs/context/ARCHITECTURE.md` | 理解设计意图，避免误判 |
| 性能优化 | `docs/context/QUICK_CONTEXT.md` | 了解基线数据 |
| 架构治理 | `docs/context/ARCHITECTURE.md` + `docs/context/DATA_FLOW.md` | 理解当前分层和数据流 |
| 功能开发 | `docs/context/GLOSSARY.md` | 理解现有类型和命名 |

### 分发 analyzer

```
主 Agent → analyzer 子 Agent:
  - 分析范围（文件清单或目录）
  - 分析视角（审计/架构/性能/并发）
  - 需要加载的 Skill
  - 输出路径
```

### 并行策略

当分析范围 > 30 文件时，按模块拆分为 3-5 个并行 analyzer：

| 分组策略 | 适用场景 |
|---------|---------|
| 按架构层分组 | 全项目分析 |
| 按功能模块分组 | 功能专项 |
| 按文件数均匀分组 | 通用 |

每组 ≤ 25 文件，确保 analyzer 上下文窗口够用。

## Step 2: 规划拆解

### 参考历史决策

规划修复方案前，检查 `docs/topics/` 中是否有相关历史——避免重复踩坑或推翻已验证的方案：
- 搜索相关专项的 `00-overview.md` 了解已有优化

### 汇总去重

读取所有 analyzer 报告，执行：

1. **跨模块去重**：同一根因的发现合并为单一任务
   - 保留最高严重度
   - 影响范围取并集
   - 标注关联文件

2. **依赖排序**：构建修复依赖图
   ```
   Quick Wins（风险最低）
     → 安全性修复（不依赖架构变更）
       → 并发修复（可能引入 async 化）
         → 架构修复（可能改变类型定义）
           → DRY 消除（依赖架构稳定后才提取）
             → 清理收尾（最后，变更范围大）
   ```

3. **分 Round**：每 Round 是一次 fixer 调用
   - 单 Round ≤ 10 个任务
   - 有依赖关系的任务在同一 Round 或按序排在前面的 Round

### 输出格式

```markdown
## Round N: {主题}

### Task N.1: {标题}
- 文件: `path/to/file.swift`
- 问题: {一句话}
- 修复: {具体方案，含代码片段}
- 依赖: {前置 Task 编号，无则写"无"}

### Task N.2: ...
```

## Step 3: 分批执行

### 分发 fixer

每 Round 构建 fixer prompt：

```
主 Agent → fixer 子 Agent:
  1. 任务清单（本 Round 的所有 Task）
  2. 前序已修清单（之前 Round 修了什么，避免重复）
  3. 需要加载的 Skill（如 code-quality-audit、swift-concurrency-expert）
  4. 分批建议（哪些 Task 可以合并为一个 Batch）
```

### 已修清单维护

每 Round 完成后，主 Agent 追加记录：

```markdown
**Round N 已修**:
- `file1.swift` → 具体改了什么
- `file2.swift` → 具体改了什么
- ⚠️ `file3.swift` → 跳过，原因
```

## Step 4: 验证确认（反馈闭环）

> **设计原理**：Harness Engineering 的核心是闭环——修改必须被验证，验证结果必须回流。
> 但闭环不能太重（每 Round 都全量复审会拖垮效率），关键是**分级验证**。

### 4a. 基本验证（每 Round 自动）

fixer 已在其 Step 4 做了编译验证。主 Agent 确认：
- [ ] fixer 报告构建通过
- [ ] commit 已提交
- [ ] 无需要主 Agent 决策的安全阀事项

**如果 fixer 汇报中标注了 `⚠️ 建议复审`** → 进入 4b。

### 4b. 修后复审（条件触发）

**触发条件**（满足任一）：
- fixer 汇报标注 `⚠️ 建议复审`
- Round 涉及架构变更（公共 API 签名、分层调整）
- Round 涉及性能关键路径修改
- 主 Agent 判断风险较高

**执行方式**：调用 analyzer 的**复审模式**：

```
主 Agent → analyzer:
  - 工作模式: 复审模式
  - 修改文件清单: [本 Round 修改的文件列表]
  - 原始问题清单: [本 Round 要修复的问题编号和描述]
  - 输出路径: .codebuddy/reports/review-round-N.md
```

### 4c. 复审结果处理

```
analyzer 复审报告
  │
  ├── 全部问题已消除 + 无新问题 → ✅ 进入下一 Round
  │
  ├── 部分问题未消除 → 追加到当前规划，插入补修 Round
  │   （补修 Round 编号: N.1, N.2, ...，保持可追溯）
  │
  ├── 发现新引入问题 → 评估严重度
  │   ├── P0/P1 → 立即插入修复 Round
  │   └── P2 → 记录到待办，不阻塞当前专项
  │
  └── 复审发现原始分析有误报 → 记录为经验教训（Step 5）
```

### 4d. 最终验证（全部 Round 结束后，可选）

当专项涉及 **3 个以上 Round** 或 **跨多个架构层**时，建议做一次轻量级最终验证：

```
主 Agent → analyzer:
  - 工作模式: 复审模式
  - 修改文件清单: [全专项修改的文件并集]
  - 原始问题清单: [全部问题编号]
  - 视角: 重点检查跨 Round 修改之间的一致性
```

**不需要最终验证的场景**：单 Round 专项、纯 Quick Wins（删冗余 import/死代码）。

## Step 5: 记录沉淀

### 更新文档（双向同步）

根据专项类型，同步更新 **活动记录** 和 **系统快照**（参考 documentation-hierarchy rule）：

| 专项类型 | topics/ 记录活动 | context/ 同步现状 |
|---------|-----------------|------------------|
| 代码质量 | `topics/engineering/` | `ARCHITECTURE.md`（如架构变更） |
| 性能优化 | `topics/performance/` | `QUICK_CONTEXT.md`（性能指标） |
| 搜索升级 | `topics/features/` | `DATA_FLOW.md` + `ARCHITECTURE.md` |
| 准确度优化 | `topics/accuracy/` | `DATA_FLOW.md` |
| UI 重构 | `topics/ui/` | 无需同步（UI 体现在代码中） |
| 测试建设 | `topics/engineering/` | — |

**topics/ 写入格式**（追加到对应模块文件）：
```markdown
### {优化点标题}
**问题**: 遇到了什么
**方案**: 怎么解决的
**成果**: 量化效果
**代码位置**: 在哪里实现
**版本**: vX.X (日期)
```

**context/ 写入原则**：只更新"现状"描述，不记录历史。

### 记录经验教训

工具链经验 → 如属于项目规则，落入 `rules/`；如属于工具链行为，直接更新 `agents/` 或 `skills/`。

## 模式库

### 模式 1: 审计-修复循环

最常见模式，适用于代码质量、并发安全、架构治理。

```
analyzer(全项目, 代码质量) → 规划(6 Round) → fixer×6 → 验证
```

### 模式 2: 增量优化

适用于性能优化、准确度提升。

```
基线测量 → analyzer(热点定位) → fixer(单点优化) → 测量 → 循环
```

### 模式 3: 功能开发

适用于新功能实现。

```
需求分析 → 契约设计(Foundation) → 核心实现(Engine) → 基础设施(Infrastructure) → UI(Presentation)
```

参考 `docs/AI_WORKFLOW.md` 的详细流程。

## 反模式

- ❌ 一次分发 > 15 个任务给 fixer（上下文溢出）
- ❌ 不传已修清单（导致重复修复）
- ❌ 跳过 Step 0 环境检查（脏工作区导致冲突）
- ❌ 在规划阶段就调用 fixer（先想清楚再动手）
- ❌ 修复后不更新文档（文档和代码脱节）
