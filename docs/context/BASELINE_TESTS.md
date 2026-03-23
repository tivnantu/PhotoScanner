# Baseline Test 说明

> 本文档记录 `PhotoScanner` 当前 Chinese-CLIP 基线回归测试的目标、覆盖范围、产物位置与执行方式。  
> 只描述当前已确认的稳定事实，不展开产品规划。

## 1. 目的

Baseline Test 用来验证：**iOS 侧 `Plugin` 层实现出的 Chinese-CLIP 能力，是否与 Python 参考输出保持一致**。

当前这组测试的目标不是验证 UI，也不是验证完整产品链路，而是验证模型底层能力没有漂移。

## 2. 覆盖范围

当前 `ChineseCLIPBaselineTests` 覆盖 5 类能力：

- `tokenizer`
- `text embedding`
- `image preprocess`
- `image embedding`
- `similarity`

对应关系如下：

- `ChineseCLIPTokenizer.swift` → `tokenizer`
- `ChineseCLIPImagePreprocessor.swift` → `image preprocess`
- `ChineseCLIPPlugin.swift` → `text embedding` / `image embedding`
- `EmbeddingService.swift` → 归一化后的统一调用门面
- `ChineseCLIPBaselineTests.swift` → iOS 侧回归测试入口

**不在当前覆盖范围内的内容**：

- `SwiftUI` 页面交互
- 正式产品搜索流程
- 索引构建 / `VectorStore` / `SearchEngine`
- `EmptyModelPlugin` 的 fallback 行为

## 3. 测试链路

当前链路可以简单理解为：

`baseline_seed.json` → `generate_chineseclip_baseline.py` → `baseline.json` → `ChineseCLIPBaselineTests`

含义分别是：

- **`baseline_seed.json`**：声明样本、模型路径和测试输入
- **`generate_chineseclip_baseline.py`**：用 Python + ONNX 生成参考输出
- **`baseline.json`**：iOS 侧回归测试读取的 golden 数据
- **`ChineseCLIPBaselineTests`**：在 iOS 侧读取 golden，并对真实实现做一致性校验

## 4. 目录与产物

### 基线数据

- `PhotoScannerTests/Baseline/ChineseCLIP/baseline_seed.json`
- `PhotoScannerTests/Baseline/ChineseCLIP/baseline.json`
- `PhotoScannerTests/Baseline/ChineseCLIP/images/festival.jpg`
- `PhotoScannerTests/Baseline/ChineseCLIP/preprocessed/festival.f32le.bin`

### Python 生成工具

- `PhotoScannerTests/Tools/generate_chineseclip_baseline.py`
- `PhotoScannerTests/Tools/pyproject.toml`
- `PhotoScannerTests/Tools/uv.lock`

### iOS 测试入口

- `PhotoScannerTests/ChineseCLIPBaselineTests.swift`
- `PhotoScannerTests/Support/`

## 5. 执行方式

### 5.1 生成 / 刷新 Python 参考输出

在 `PhotoScannerTests/Tools/` 下执行：

```bash
cd PhotoScannerTests/Tools
uv sync
uv run generate_chineseclip_baseline.py
```

说明：

- `uv` 默认虚拟环境目录为 `PhotoScannerTests/Tools/.venv`
- 默认输入是 `PhotoScannerTests/Baseline/ChineseCLIP/baseline_seed.json`
- 默认输出会覆盖同目录下的 `baseline.json`

### 5.2 执行 iOS 侧回归测试

当前建议在 **Xcode 真机环境** 下运行 `ChineseCLIPBaselineTests`。

重点关注以下断言是否全部通过：

- `report.tokenizerPassed`
- `report.textEmbeddingPassed`
- `report.imagePreprocessPassed`
- `report.imageEmbeddingPassed`
- `report.similarityPassed`
- `report.isPassing`

## 6. 当前结论

当前 Baseline Test 的定位是：**为 `Plugin` 层的 Chinese-CLIP 实现提供可重复执行的一致性回归能力**。

只要这组测试持续通过，就说明当前 iOS 侧底模链路在以下方面仍与 Python 参考保持一致：

- 分词
- 图像预处理
- 向量编码
- 最终相似度计算
