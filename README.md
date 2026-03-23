# PhotoScanner

基于 Chinese-CLIP 的本地照片智能检索 iOS App。在设备端运行图文双塔模型，支持用中文描述搜索手机相册中的照片。

## 做什么

- **文搜图**：输入中文文本，从相册中找到语义匹配的照片
- **图搜图**：选择一张照片，找到视觉相似的其他照片
- **全部本地**：模型推理和向量检索均在设备端完成，照片不出手机

## 用了什么

| 技术 | 说明 |
|------|------|
| **Chinese-CLIP ViT-B/16** | 中文图文跨模态预训练模型，双塔 ONNX 格式 |
| **ONNX Runtime Mobile** | iOS 端模型推理运行时 |
| **SwiftUI** | 界面框架，iOS 26+ |
| **Swift Concurrency** | actor 隔离 + async/await 并发模型 |

## 架构

四层单向依赖：`Presentation → Engine → Plugin → Foundation`

- **Plugin** 封装模型细节（ONNX / CoreML），通过 `ModelPlugin` 协议暴露能力
- **Engine** 提供业务门面（embedding、相似度），不知道底层实现
- 详见 [`docs/context/ARCHITECTURE.md`](docs/context/ARCHITECTURE.md)

## 构建

- Xcode 26.0+，iOS 26.0+
- 真机构建（模型文件约 726MB，通过 Git LFS 管理）

## 项目知识

工程细节、模型参数、数据链路与 Baseline Test 说明等沉淀在 [`docs/context/`](docs/context/) 目录：

- 架构设计：[`docs/context/ARCHITECTURE.md`](docs/context/ARCHITECTURE.md)
- 模型参数：[`docs/context/MODEL_SPECS.md`](docs/context/MODEL_SPECS.md)
- Baseline Test：[`docs/context/BASELINE_TESTS.md`](docs/context/BASELINE_TESTS.md)
