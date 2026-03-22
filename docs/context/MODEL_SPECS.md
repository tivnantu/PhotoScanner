# Chinese-CLIP 模型技术参数

> 本文档记录当前工程使用的底模核心参数。  
> 所有数值均从 Chinese-CLIP 官方源码提取，iOS 侧实现必须严格对齐。

## 来源

| 项目 | 链接 |
|------|------|
| 官方仓库 | https://github.com/OFA-Sys/Chinese-CLIP |
| 论文 | https://arxiv.org/abs/2211.01335 |
| HuggingFace | https://huggingface.co/OFA-Sys/chinese-clip-vit-base-patch16 |

## 当前选型

| 属性 | 值 |
|------|-----|
| 模型名称 | `chinese-clip-vit-base-patch16` |
| 视觉编码器 | ViT-B/16 |
| 文本编码器 | RoBERTa-wwm-ext-base-chinese |
| 模型格式 | ONNX (FP32)，双塔独立文件 |
| 运行时 | ONNX Runtime Mobile (`onnxruntime-swift-package-manager` v1.24.2) |

## 核心参数速查

### Embedding

| 参数 | 值 | 来源 |
|------|----|------|
| embedding 维度 | **512** | `ViT-B-16.json` → `embed_dim` |
| logit_scale 初始值 | ln(1/0.07) ≈ 2.6593 | `model.py` |

### 图像塔

| 参数 | 值 | 来源 |
|------|----|------|
| 输入尺寸 | **224 × 224** | `ViT-B-16.json` → `image_resolution` |
| 通道顺序 | RGB, CHW (NCHW with batch) | `image_transform` 函数 |
| Resize 插值 | Bicubic | `InterpolationMode.BICUBIC` |
| Normalize mean | `(0.48145466, 0.4578275, 0.40821073)` | `utils.py:179` |
| Normalize std | `(0.26862954, 0.26130258, 0.27577711)` | `utils.py:179` |
| ONNX 输入名 | `image` | `pytorch_to_onnx.py` |
| ONNX 输入 shape | `[B, 3, 224, 224]`, float32 | 同上 |
| ONNX 输出名 | `unnorm_image_features` | 同上 |
| ONNX 输出 shape | `[B, 512]`, float32 | 同上 |

### 文本塔

| 参数 | 值 | 来源 |
|------|----|------|
| Tokenizer 类型 | Bert WordPiece (`FullTokenizer`) | `bert_tokenizer.py` |
| do_lower_case | `true` | 同上 |
| context_length | **52**（含 `[CLS]` + `[SEP]`） | `utils.py:145` |
| vocab 大小 | **21128** | `vocab.txt` 行数 |
| 编码格式 | `[CLS] + tokens[:50] + [SEP] + [PAD]...` | `utils.py:163` |
| ONNX 输入名 | `text` | `pytorch_to_onnx.py` |
| ONNX 输入 shape | `[B, 52]`, int64 | 同上 |
| ONNX 输出名 | `unnorm_text_features` | 同上 |
| ONNX 输出 shape | `[B, 512]`, float32 | 同上 |

### 后处理

| 步骤 | 说明 | 来源 |
|------|------|------|
| L2 归一化 | 对 image/text embedding 分别做 L2 normalize | `model.py:forward` |
| 相似度计算 | 归一化后向量的点积即为余弦相似度 | `extract_features_onnx.py` |

## Tokenizer 实现要点

> ⚠️ Tokenizer 一致性是结果准确性的最大风险点。

Chinese-CLIP 使用自实现的 `FullTokenizer`（等价于 Bert WordPiece），流程：

1. **BasicTokenizer**
   - 中文字符逐字拆分（每个 CJK 字符前后加空格）
   - 全角转半角
   - 转小写
   - 去除 Unicode 音标（accent stripping）
   - 按空白和标点切分
2. **WordpieceTokenizer**
   - 对每个 token 用 `##` 前缀做子词匹配
   - 未知 token 映射为 `[UNK]`
3. **编码**
   - 拼接 `[CLS]` (id=101) + token_ids + `[SEP]` (id=102)
   - 截断到 context_length (52)
   - 不足部分用 `[PAD]` (id=0) 填充

## 预处理流水线（Python 参考）

```python
# 图像预处理 — 来自 cn_clip/clip/utils.py:image_transform
transform = Compose([
    Resize((resolution, resolution), interpolation=InterpolationMode.BICUBIC),
    _convert_to_rgb,
    ToTensor(),
    Normalize(mean=(0.48145466, 0.4578275, 0.40821073),
              std=(0.26862954, 0.26130258, 0.27577711)),
])

# 文本编码 — 来自 cn_clip/clip/utils.py:tokenize
tokens = tokenizer.tokenize(text)
tokens = [tokenizer.vocab["[CLS]"]] + tokens[:context_length-2] + [tokenizer.vocab["[SEP]"]]
tokens += [0] * (context_length - len(tokens))  # PAD
```

## 其他模型变体（备查）

| 模型 | embed_dim | image_size | vision_layers | text_model |
|------|-----------|-----------|---------------|------------|
| **ViT-B-16（当前）** | 512 | 224 | 12 | RoBERTa-base (12L, 768) |
| ViT-L-14 | 768 | 224 | 24 | RoBERTa-base (12L, 768) |
| ViT-L-14-336 | 768 | 336 | 24 | RoBERTa-base (12L, 768) |
| ViT-H-14 | 1024 | 224 | 32 | RoBERTa-large (24L, 1024) |
