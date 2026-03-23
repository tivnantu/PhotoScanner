# AI 开发工作流

> 🔄 本文件是 **AI 工具链组件**，供 Agent 按需读取。
> 定位：功能开发 / Bug 修复 / 重构的实施流程。
>
> 相关组件：
> - 问题诊断路由 → `AI_ROUTING.md`

## 架构分层

```
├── Foundation/          # 基础类型和配置
│   ├── Embedding.swift  # 嵌入向量值对象
│   ├── SimilarityScore.swift  # 相似度计算
│   ├── ResourceBudget.swift   # 资源预算
│   ├── Errors.swift     # 错误定义
│   └── Logger.swift     # 日志分类
│
├── Engine/              # 核心业务逻辑
│   ├── Indexing/        # 索引构建
│   ├── Search/          # 搜索执行
│   └── Preprocessing/   # 图像预处理
│
├── Infrastructure/      # 技术基础设施
│   ├── Cache/           # 缓存实现
│   ├── System/          # 系统监控
│   ├── Performance/     # ANE 兼容检测
│   └── Debug/           # 调试工具
│
├── Presentation/        # UI 层
│   ├── Components/      # 通用组件
│   ├── Design/          # 设计常量
│   └── *View/           # 各功能页面
│
└── Plugin/              # AI 模型插件
    └── ChineseCLIP*/    # Chinese-CLIP 相关
```

## 新功能开发流程

### Step 1: 需求分析（1分钟）

**判断功能类型**:
```
用户: 我想添加 XX 功能

├── 搜索相关？
│   ├── 新搜索模式 → 阅读 Engine/Search/
│   └── 新排序方式 → 阅读 SimilarityScore
│
├── 索引相关？
│   ├── 新索引类型 → 阅读 Engine/Indexing/
│   └── 新预处理 → 阅读 Engine/Preprocessing/
│
├── UI相关？
│   ├── 新页面 → 阅读 Presentation/
│   └── 新组件 → 阅读 Presentation/Components/
│
├── 性能相关？
│   ├── 优化速度 → 阅读 Infrastructure/Cache/
│   └── 优化内存 → 阅读 ResourceBudget
│
└── 模型相关？
    └── 新模型 → 阅读 Plugin/ 目录结构
```

### Step 2: 类型定义（Foundation层）

**决策树**:
```
需要什么？
├── 新数据类型？
│   └── Foundation/ 创建值对象
│       - 遵循 Value Object 模式（不可变）
│       - 实现 Sendable, Equatable, Codable
│
├── 新配置项？
│   └── Foundation/ 添加配置
│       - 使用 struct + Sendable
│       - 提供默认值
│
├── 新错误类型？
│   └── Foundation/Errors.swift 添加 case
│       - 提供用户友好的描述
│
└── 新日志分类？
    └── Foundation/Logger.swift 添加 static let
```

### Step 3: 核心逻辑（Engine层）

```
Engine/{子系统}/ 创建或修改

模板:
actor NewService: Sendable {
    // 状态隔离
    private var state: SomeState
    
    // 依赖注入
    init(dependency: SomeDependency) {}
    
    // 公共方法
    func perform(input: SomeInput) async throws -> SomeOutput {}
}
```

### Step 4: 基础设施（Infrastructure层）

```
根据功能选择目录:
├── 缓存相关 → Infrastructure/Cache/
├── 系统监控 → Infrastructure/System/
├── 性能检测 → Infrastructure/Performance/
└── 调试工具 → Infrastructure/Debug/

实现要求:
- 使用 actor 隔离可变状态
- 使用 Logger.{category} 记录日志
- 使用 PSError 错误类型
```

### Step 5: UI 实现（Presentation层）

```
Presentation/{功能}/ 创建视图和 ViewModel

模板:
@Observable
class FeatureViewModel {
    // 状态
    var state: FeatureState = .idle
    
    // 业务逻辑委托
    func performAction() async {}
}

struct FeatureView: View {
    @State private var viewModel = FeatureViewModel()
    
    var body: some View { ... }
}
```

## Bug 修复流程

### 诊断阶段

```
1. 复现问题
2. 定位层级:
   - Foundation层？→ 检查类型定义
   - Engine层？→ 检查业务逻辑
   - Infrastructure层？→ 检查技术实现
   - Presentation层？→ 检查视图状态
3. 检查 EDGE_CASES.md 是否已知问题
```

### 修复阶段

```
1. 添加/更新测试（复现问题）
2. 修复代码
3. 验证测试通过
4. 更新相关文档（如需要）
```

## 重构流程

```
触发条件:
- 代码重复
- 职责不清
- 性能瓶颈

步骤:
1. 确保有测试覆盖（先写测试）
2. 小步重构，频繁验证
3. 更新 ARCHITECTURE.md（架构变更）
```

## 代码审查清单

```
□ 遵循分层结构（Foundation/Engine/Infrastructure/Presentation）
□ 可变状态使用 actor 隔离
□ 日志使用分类 Logger.{category}
□ 错误使用 PSError 枚举
□ 注释解释"为什么"而非"是什么"
□ 核心链路日志不偷懒
```
