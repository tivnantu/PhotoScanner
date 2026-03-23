# PhotoScanner AI 工具链

> AI 辅助工程专项执行的基础设施。日常编码规范见项目根目录 `AGENTS.md`。

## 架构概览

```
.codebuddy/
├── agents/          角色（能力边界）
│   ├── analyzer.md    只读分析专家（审计/架构/性能/并发，编排+对话双模式）
│   └── fixer.md       代码修改执行者（修复/重构/消债，构建验证+自动 commit）
│
├── skills/          领域知识（方法论，按需加载，分类见下）
│
├── rules/           红线约束（自动注入每次对话）
│   ├── code-quality-standards.mdc    安全/并发/架构/DI/性能红线
│   └── documentation-hierarchy.mdc   五层级文档维护规范（核心原则）
│
└── reports/         分析报告（gitignore，临时产物）
```

## 核心设计原则

### 1. 概念正交，不杂糅

| 概念 | 对应 | 职责 | 变更频率 |
|------|------|------|---------|
| 角色 | agents/ | 定义"谁来做"——能力边界（只读 vs 读写） | 低 |
| 知识 | skills/ | 定义"怎么做"——方法论，可插拔组合 | 中 |
| 红线 | rules/ | 定义"不能做什么"——自动注入，无需手动加载 | 极低 |

### 2. 单一事实来源（SSOT）

每条信息只在一个地方**定义**，其他地方通过**引用**获取：

| 信息类型 | 权威源 | 引用方式 |
|---------|--------|---------|
| 编码红线 | `rules/code-quality-standards.mdc` | agents 声明"已由 rule 自动注入" |
| 编码原则 | `AGENTS.md` | skills 标注"权威源：AGENTS.md" |
| 文档同步规则 | `rules/documentation-hierarchy.mdc` | AGENTS.md / AI_WORKFLOW.md 标注引用 |
| 项目参数 | `docs/context/QUICK_CONTEXT.md` | AGENTS.md 标注"权威源：QUICK_CONTEXT.md" |

**速查摘要允许适度冗余**（提高韧性），但必须标注权威源。

### 3. 动态发现，不硬编码

工具链只编码**方法论**（稳定），不编码**具体事实**（易变）：

- 具体参数 → agent 运行时读 `Engine/` 或 `Foundation/`
- 具体热点 → agent 运行时用 `rg`/`codebase_search` 发现
- 环境信息 → `xcrun devicectl list devices`/`ls -d *.xcodeproj` 动态获取
- 设计意图 → agent 按需读 `docs/context/` 对应文档

### 4. 自举闭环与熵减

```
执行 → 踩坑 → 更新 agents/skills/rules
  ↑                       ↓
  └─── 下次执行时遵循 ←────┘
```

工具链自身也可以被修改——本文件就是这样迭代优化的。

#### 熵减意识

代码库随时间自然趋向混乱（熵增）。AI 驱动的修改放大了这个趋势——速度更快，产出更多，偏差也可能更快积累。主 Agent 在以下**自然节点**执行轻量级熵减：

| 时机 | 做什么 | 不做什么 |
|------|--------|---------|
| 工程专项完成后 | 扫描遗留的 TODO/FIXME，确认是有意保留还是遗漏 | 不做全面审计 |
| 大批量修改后（>10 文件） | 检查 import 是否有冗余、命名是否一致 | 不追求完美 |
| 新增 skill/rule 后 | 检查是否与现有内容有信息冲突 | 不重构整个工具链 |
| 用户反馈"感觉不对"时 | 针对性检查相关模块 | 不扩大范围 |

> 熵减是**习惯**，不是流程。不需要每次都做，但在上述节点时**想一想**。

## Skills 分类

### 项目知识（理解本项目）

| Skill | 用途 |
|-------|------|
| `project-knowledge` | 项目知识速查 + 五层级文档导航 |
| `code-quality-audit` | 9 维度审查方法论 + 修复决策树 |
| `engineering-workflow` | 工程专项执行五步法（编排器用） |

### 语言与框架（Swift / SwiftUI 专业知识）

| Skill | 用途 |
|-------|------|
| `swift-concurrency-expert` | Swift 6.2+ 并发审查与修复（actor 隔离、Sendable、数据竞争） |
| `swiftui-performance-audit` | SwiftUI 性能审计（渲染分析、Instruments 配置） |
| `swiftui-view-refactor` | View 重构规范（MV 优先、子 View 提取、稳定视图树） |
| `swiftui-ui-patterns` | SwiftUI 组件模式（导航、Sheet、列表、表单等 26+ 参考文档） |
| `swiftui-liquid-glass` | iOS 26+ Liquid Glass API（毛玻璃效果、GlassEffectContainer） |

### 工具集成（构建 / 运行 / 调试）

| Skill | 用途 |
|-------|------|
| `xcodebuildmcp` | XcodeBuildMCP 官方 skill（构建/测试/调试/运行/日志/UI自动化） |

## 组合元规则

面对任务时，AI 按以下原则选择和组合 skills——不需要预定义每条路径：

```
1. 先上下文：是否需要项目知识类 skill 提供背景？
   → project-knowledge 提供导航，按需读 docs/context/

2. 再方法论：任务领域是否匹配语言框架类 skill？
   → 并发问题 → swift-concurrency-expert
   → View 重构 → swiftui-view-refactor
   → 性能问题 → swiftui-performance-audit

3. 执行时：需要构建/运行/调试？
   → xcodebuildmcp-cli

4. 组合原则：先加载知识，再加载方法论，最后执行
   → 不要一次性加载所有 skill，保留上下文给源代码
```

**自举**：当发现新的组合模式时，在此追加。当新增 skill 时，归入上述分类。

## Agent 协作模型

### 编排模式（工程专项）

```
主 Agent（编排器，高推理模型）
  ├── 分发 analyzer × N（并行只读分析）
  ├── 汇总去重 + 规划
  ├── 分发 fixer × M（分批修改 + 构建验证 + 自动 commit）
  ├── 条件触发 analyzer 复审（fixer 标记"建议复审"时）
  │   └── 复审发现问题 → 插入补修 Round → 再验证
  └── 记录沉淀（docs/）
```

详细流程 → `use_skill engineering-workflow`

### 对话模式（日常使用）

```
用户 → analyzer: "帮我看看这个文件有没有问题"
analyzer → 用户: 直接回复分析结果，支持多轮追问
```

| 角色 | 工具权限 | 模型策略 |
|------|---------|---------|
| 主 Agent | 全部 | 高推理（编排决策） |
| analyzer | 只读 + write_to_file(报告) | 中等（分析够用） |
| fixer | 完整读写 | 经济型（按指令执行） |

## 与项目文档体系的关系

工具链在正确时机引导 agent 读取正确的项目文档：

```
README.md           → 项目概览（首次接触时）
AGENTS.md           → 编码原则（写代码前）
docs/context/       → 系统现状（分析/修改前）
docs/topics/        → 开发历史（遇到不理解的设计决策时）
代码                → 最权威的事实（需要具体细节时）
```

详见 `skills/project-knowledge/skill.md` 中的五层级文档导航。

## Git 管理策略

| 内容 | 策略 | 理由 |
|------|------|------|
| agents/ skills/ rules/ | 提交 | 工具链定义，团队共享 |

## 演进历史

1. **v0** — 初始版本：analyzer + fixer 双角色架构，核心 skills
