# PhotoScanner 快速上下文

> 最小必要信息，用于快速理解项目。~2K tokens。

## 项目定位

iOS 图片搜索应用，基于 Chinese-CLIP 实现图文检索和图图对比。

## 核心技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI + Observation |
| 并发 | Swift 6 + actor |
| 向量搜索 | HNSW 索引 |
| 图片预处理 | vImage + vDSP |
| 模型推理 | CoreML (Chinese-CLIP) |
| 存储 | JSON + mmap |

## 架构分层

```
Foundation/       基础类型（Embedding, SimilarityScore, ResourceBudget, Errors, Logger）
Engine/           核心逻辑（Indexing, Search, Preprocessing）
Infrastructure/   技术设施（Cache, System, Performance, Debug）
Presentation/     UI（Views, ViewModels, Components, Design）
Plugin/           AI 模型插件（ChineseCLIP*）
```

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 图片尺寸 | 256×256 | vImage 预处理 |
| Token 长度 | 72 | XLM-RoBERTa |
| Embedding 维度 | 768 | Chinese-CLIP |
| HNSW M | 16 | 每层连接数 |
| HNSW efConstruction | 200 | 构建时搜索范围 |
| HNSW efSearch | 50 | 搜索时搜索范围 |
| 搜索延迟 | ~45ms | P95 目标 |
| 索引速度 | ~10 张/秒 | 真机实测 |
| 内存预算 | 260 MB | Embedding + 缩略图 + 模型 |
| 最低 iOS | 26.0 | 无版本适配 |
| 最低设备 | iPhone 14 Pro | 无设备分级 |

## 相似度计算

```swift
// 图文检索：高斜率 Sigmoid（放大差异便于排序）
let logit = cosine * 98.864479 + (-10.0)
let score = 1.0 / (1.0 + exp(-logit))

// 图图对比：温和刻度（直观展示）
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

## 性能优化亮点

| 优化 | 技术 | 收益 |
|------|------|------|
| 向量加速 | vDSP | 20-30x |
| 图片预处理 | vImage | 6.7x |
| 向量搜索 | HNSW | O(log N) |
| 缓存命中 | 双级缓存 | >90% |
| 内存保护 | ThermalThrottler | 防崩溃 |

## 文件组织

```
PhotoScanner/
├── Foundation/
│   ├── Embedding.swift           # 嵌入向量值对象
│   ├── SimilarityScore.swift     # 相似度计算
│   ├── ResourceBudget.swift      # 资源预算
│   ├── Errors.swift              # 错误定义
│   └── Logger.swift              # 日志门面
├── Engine/
│   ├── Indexing/                 # 索引构建
│   │   ├── HNSWIndex.swift       # HNSW 向量索引
│   │   └── IndexCheckpoint*.swift # 断点续传
│   ├── Search/                   # 搜索执行
│   └── Preprocessing/            # 图像预处理
├── Infrastructure/
│   ├── Cache/                    # 缓存实现
│   ├── System/                   # 系统监控
│   └── Performance/              # ANE 检测
└── Presentation/
    └── Components/               # UI 组件
```

## 构建要求

- **仅真机构建**：不支持 iOS Simulator
- **设备**：ta_iPhone14
- **命令**：`xcodebuild -destination 'platform=iOS,name=ta_iPhone14'`
