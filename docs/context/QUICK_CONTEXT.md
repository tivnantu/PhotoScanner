# PhotoScanner 快速上下文

> 最小必要信息，用于快速理解项目。~2K tokens。

## 项目定位

iOS 图片搜索应用，基于 Chinese-CLIP ViT-B/16 实现图文检索。

## 核心技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI + Observation |
| 并发 | Swift 6 + actor |
| 向量搜索 | mmap + 暴力检索 / HNSW（备用） |
| 图片预处理 | vImage + vDSP |
| 模型推理 | ONNX Runtime (Chinese-CLIP) |
| 存储 | JSON + mmap |

## 架构分层

```
Foundation/       基础类型（Embedding, Errors, Logger, SimdUtils）
Engine/           核心逻辑（Indexing, Search, EmbeddingService）
Infrastructure/   技术设施（Cache, System, Performance）
Presentation/     UI（Views, ViewModels）
Plugin/           AI 模型（ChineseCLIP*）
```

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 图片尺寸 | 224×224 | 模型输入 |
| Token 长度 | 52 | 含 [CLS]/[SEP] |
| Embedding 维度 | **512** | Chinese-CLIP ViT-B/16 |
| 搜索延迟 | ~45ms | P95 目标 |
| 索引速度 | ~10 张/秒 | 真机实测 |
| 内存预算 | 260 MB | Embedding + 缩略图 + 模型 |
| 最低 iOS | 26.0 | Swift 6 严格并发 |
| 最低设备 | iPhone 14 Pro | ANE 加速 |

## 模型参数

| 参数 | 值 | 来源 |
|------|-----|------|
| 视觉编码器 | ViT-B/16 | 12 层, 768 隐藏层 |
| 文本编码器 | RoBERTa-wwm-base | 12 层, 768 隐藏层 |
| 输出维度 | 512 | embed_dim |
| 图像均值 | [0.4815, 0.4578, 0.4082] | RGB |
| 图像标准差 | [0.2686, 0.2613, 0.2758] | RGB |

## 相似度计算

```swift
// 图文检索：高斜率 Sigmoid
let logit = cosine * 98.864479 + (-10.0)
let score = 1.0 / (1.0 + exp(-logit))

// 图图对比：温和刻度
let logit = cosine * 4.0 + 1.5
let score = 1.0 / (1.0 + exp(-logit))
```

## 日志分类

```swift
Logger.app      // 应用生命周期
Logger.model    // 模型推理
Logger.search   // 搜索执行
Logger.index    // 索引构建
Logger.vision   // 图片预处理
Logger.ui       // UI 交互
Logger.system   // 系统事件
```

## 性能优化

| 优化 | 技术 | 收益 |
|------|------|------|
| 向量计算 | vDSP | 20-30x |
| 图片预处理 | vImage | 6.7x |
| 向量搜索 | mmap | 内存效率 |
| 缓存 | 双级缓存 | >90% 命中 |

## 构建要求

- **仅真机构建**：使用 Photos 框架，不支持 Simulator
- **设备**：iPhone 真机
- **命令**：`xcodebuild -destination 'platform=iOS,name=<设备名>'`

## 关键文件速查

| 文件 | 用途 |
|------|------|
| `ChineseCLIPPlugin.swift` | 模型推理入口 |
| `EmbeddingService.swift` | embedding 统一门面 |
| `SearchEngine.swift` | 文搜图编排 |
| `IndexEngine.swift` | 索引构建编排 |
| `MMapBruteForceVectorStore.swift` | 向量检索实现 |
| `PhotoScannerApp.swift` | 依赖注入组装点 |
