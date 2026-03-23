# Baseline Test 说明

> 验证 iOS 侧 Chinese-CLIP 实现与 Python 参考输出的一致性。

## 目的

确保 `Plugin` 层实现与官方 Chinese-CLIP 模型输出保持一致。

## 覆盖范围

当前覆盖 5 类能力：

| 能力 | 对应文件 |
|------|----------|
| tokenizer | `ChineseCLIPTokenizer.swift` |
| image preprocess | `ChineseCLIPImagePreprocessor.swift` |
| text embedding | `ChineseCLIPPlugin.encodeText` |
| image embedding | `ChineseCLIPPlugin.encodeImage` |
| similarity | 端到端相似度计算 |

**不在范围内**：
- SwiftUI 页面交互
- 索引构建 / 搜索流程
- `EmptyModelPlugin` fallback

## 测试链路

```
baseline_seed.json → generate_chineseclip_baseline.py → baseline.json → ChineseCLIPBaselineTests
```

| 文件 | 说明 |
|------|------|
| `baseline_seed.json` | 声明样本、模型路径和测试输入 |
| `generate_chineseclip_baseline.py` | Python + ONNX 生成参考输出 |
| `baseline.json` | iOS 侧回归测试读取的 golden 数据 |
| `ChineseCLIPBaselineTests` | iOS 侧一致性校验 |

## 目录结构

```
PhotoScannerTests/
├── Baseline/ChineseCLIP/
│   ├── baseline_seed.json
│   ├── baseline.json
│   └── images/
├── Tools/
│   ├── generate_chineseclip_baseline.py
│   └── pyproject.toml
└── ChineseCLIPBaselineTests.swift
```

## 执行方式

### 生成 Python 参考输出

```bash
cd PhotoScannerTests/Tools
uv sync
uv run generate_chineseclip_baseline.py
```

### 执行 iOS 回归测试

Xcode 真机环境运行 `ChineseCLIPBaselineTests`。

关键断言：
- `report.tokenizerPassed`
- `report.textEmbeddingPassed`
- `report.imagePreprocessPassed`
- `report.imageEmbeddingPassed`
- `report.similarityPassed`
- `report.isPassing`

## 当前结论

Baseline Test 为 `Plugin` 层 Chinese-CLIP 实现提供一致性回归能力。

通过条件：
- 分词结果一致
- 图像预处理结果一致
- 向量编码结果一致（误差 < 1e-4）
- 最终相似度计算一致
