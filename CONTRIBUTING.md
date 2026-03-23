# 贡献指南

感谢您对 PhotoScanner 的兴趣！本项目是一个基于 Chinese-CLIP 的 iOS 相册语义搜索应用。

---

## 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd PhotoScanner
```

### 2. 安装 Git LFS

模型文件使用 Git LFS 管理：

```bash
git lfs install
git lfs pull
```

### 3. 打开项目

```bash
open PhotoScanner.xcodeproj
```

### 4. 运行

- 选择连接的 iPhone 真机
- 按 `Cmd + R` 运行

> ⚠️ 本项目不支持 iOS Simulator，必须使用真机。

---

## 开发前必读

### 📘 编码规范

**详见** [`AGENTS.md`](./AGENTS.md) — AI 编码助手操作手册

**核心约定**：
- **五层架构**：Foundation → Engine → Infrastructure → Presentation ← Plugin
- **Swift 6 并发**：所有服务使用 `actor` 隔离可变状态
- **依赖注入**：构造器注入协议，禁止 `.shared` 单例
- **SwiftUI 规范**：`@Observable` + `@Environment`，View 不手动标注 `@MainActor`

### 📚 项目知识

- **快速了解项目**：[`docs/context/QUICK_CONTEXT.md`](./docs/context/QUICK_CONTEXT.md)
- **架构设计**：[`docs/context/ARCHITECTURE.md`](./docs/context/ARCHITECTURE.md)
- **术语表**：[`docs/context/GLOSSARY.md`](./docs/context/GLOSSARY.md)
- **边界场景**：[`docs/context/EDGE_CASES.md`](./docs/context/EDGE_CASES.md)

### 🔍 故障排查

遇到问题时，优先查阅 [`docs/context/EDGE_CASES.md`](./docs/context/EDGE_CASES.md)：
- 常见错误模式
- 调试步骤
- 已知陷阱

---

## 开发流程

### 1. 创建分支

```bash
git checkout -b feature/your-feature-name
# 或
git checkout -b fix/your-bug-fix
```

### 2. 开发

**添加新功能的通用流程**：
1. **定义基础类型**：`Foundation/` 定义协议和实体
2. **实现核心逻辑**：`Engine/` 实现服务（`actor` 隔离）
3. **添加基础设施**：`Infrastructure/` 缓存、监控等
4. **注入依赖**：`AppServices` 注册
5. **展示 UI**：`Presentation/` 使用 `@Environment`

### 3. 提交

```bash
git add .
git commit -m "feat: 添加功能描述"
```

**Commit 消息格式**（Conventional Commits）：
- `feat:` — 新功能
- `fix:` — Bug 修复
- `refactor:` — 重构
- `docs:` — 文档更新
- `perf:` — 性能优化
- `test:` — 测试相关
- `chore:` — 构建/工具相关

### 4. 推送并创建 PR

```bash
git push origin feature/your-feature-name
```

---

## 代码审查要点

PR 需要满足以下条件：

### ✅ 代码质量
- [ ] 遵循 `AGENTS.md` 中的编码规范
- [ ] 所有服务使用 `actor` 隔离可变状态
- [ ] 依赖通过构造器注入（无 `.shared` 单例）
- [ ] 无编译警告（Swift 6 strict concurrency）
- [ ] 无 force unwrap / try! / as!

### ✅ 功能完整性
- [ ] 功能正常工作
- [ ] 处理边界情况（权限、内存等）
- [ ] 添加适当的错误处理

### ✅ 文档更新
- [ ] 新增功能：更新 `docs/context/GLOSSARY.md`
- [ ] 架构变更：更新 `docs/context/ARCHITECTURE.md`
- [ ] 性能优化：更新 `docs/context/QUICK_CONTEXT.md`
- [ ] 新增陷阱：更新 `docs/context/EDGE_CASES.md`

---

## 架构约定

### 五层架构规则

```
Foundation/       → 基础类型和配置（纯 Swift，零外部依赖）
Engine/           → 核心业务逻辑（索引构建、搜索执行）
Infrastructure/   → 技术基础设施（缓存、监控、调试工具）
Presentation/     → UI 展示（Views, ViewModels）
Plugin/           → AI 模型插件（ChineseCLIP*）
```

**红线**（不可违反）：
- Foundation 层禁止 import `UIKit`、`Photos`、`CoreLocation`、`Vision`、`CoreML`、`ONNX`
- Engine 层禁止直接调用 `FileManager`、`PHAsset.fetchAssets` 等基础设施 API
- Presentation 层禁止执行文件 I/O 或网络操作
- 所有层禁止新增 `.shared` 单例，必须通过构造器注入协议

---

## 性能要求

### 关键指标

| 指标 | 目标 |
|------|------|
| 搜索延迟 (P95) | ≤ 45ms |
| 索引速度 | ~10 张/s |
| 图片预处理 | ≤ 5ms/张 |

---

## 问题反馈

### Bug 报告
- 提供复现步骤
- 附上日志（`Logger` 分类）
- 说明设备型号和 iOS 版本

### 功能请求
- 描述使用场景
- 说明为什么需要这个功能

---

## 许可证

本项目采用 MIT 许可证 — 详见 [`LICENSE`](./LICENSE)

---

## 致谢

感谢所有贡献者让 PhotoScanner 变得更好！🎉
