# PhotoScanner

基于 Chinese-CLIP 的本地照片智能检索 iOS App。在设备端运行图文双塔模型，支持用中文描述搜索手机相册中的照片。

## 特性

- **文搜图** — 输入中文文本，从相册中找到语义匹配的照片
- **图搜图** — 选择一张照片，找到视觉相似的其他照片
- **图文相似度** — 计算图片与文本的语义匹配分数
- **高性能** — 搜索延迟 ~45ms (P95)
- **端侧推理** — 无需网络，隐私优先

## 系统要求

- iOS 26.0+
- iPhone 14 Pro 或更高（目标设备）
- 真机运行（使用 Photos 等真机专属框架，不支持 Simulator）

## 技术栈

| 技术 | 说明 |
|------|------|
| **Chinese-CLIP ViT-B/16** | 中文图文跨模态预训练模型，双塔 ONNX 格式，512 维输出 |
| **ONNX Runtime Mobile** | iOS 端模型推理运行时 |
| **SwiftUI** | 界面框架 |
| **Swift 6 Concurrency** | actor 隔离 + async/await 并发模型 |

## 快速开始

```bash
git clone <repository-url>
cd PhotoScanner
git lfs install && git lfs pull
open PhotoScanner.xcodeproj
```

使用 Xcode 26+ 构建并运行到真机 (⌘+R)。

> ⚠️ 本项目使用 Photos 框架，不支持 iOS Simulator。必须使用真机构建和运行。

## 项目结构

```
PhotoScanner/
├── PhotoScanner/           # 源码
│   ├── Foundation/         # 基础类型和配置
│   ├── Engine/             # 核心业务逻辑
│   ├── Infrastructure/     # 技术基础设施
│   ├── Presentation/       # UI 层
│   └── Plugin/             # AI 模型插件
├── docs/
│   ├── context/            # 系统知识（稳定事实）
│   └── AI_*.md             # AI 协作指南
└── .codebuddy/             # AI 工具链
```

## 架构

五层单向依赖：

```
Presentation → Engine → Foundation ← Infrastructure ← Plugin
```

- **Foundation** — 基础类型（Embedding, Errors, Logger, 相似度计算）
- **Engine** — 核心业务逻辑（索引构建、搜索执行）
- **Infrastructure** — 技术基础设施（缓存、监控、调试工具）
- **Presentation** — UI 展示（Views, ViewModels）
- **Plugin** — AI 模型插件（ChineseCLIP*）

详见 [`docs/context/ARCHITECTURE.md`](docs/context/ARCHITECTURE.md)

## 性能指标

| 指标 | 数值 |
|------|------|
| 搜索延迟 (P95) | ~45ms |
| 索引速度 | ~10 张/s |
| 预处理时间 | ~5ms |
| Embedding 维度 | 512 |

## 文档体系

| 文档 | 说明 |
|------|------|
| [AGENTS.md](AGENTS.md) | AI 编码助手操作手册（编码原则、易错点） |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南（开发流程、代码审查） |
| [docs/context/](docs/context) | 系统知识（架构、术语表、模型规格、边界场景） |
| [docs/AI_WORKFLOW.md](docs/AI_WORKFLOW.md) | AI 开发工作流 |
| [docs/AI_ROUTING.md](docs/AI_ROUTING.md) | AI 决策路由 |

## 贡献

欢迎贡献！请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

- [Chinese-CLIP](https://github.com/OFA-Sys/Chinese-CLIP) — 中文图文预训练模型
- [ONNX Runtime](https://onnxruntime.ai/) — 推理引擎

## 许可证

[MIT](LICENSE)
