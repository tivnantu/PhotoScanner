# Chinese-CLIP 模型技术参数

> 当前工程使用的底模核心参数，iOS 侧实现必须严格对齐。

## 来源

| 项目 | 链接 |
|------|------|
| 官方仓库 | https://github.com/OFA-Sys/Chinese-CLIP |
| HuggingFace | https://huggingface.co/OFA-Sys/chinese-clip-vit-base-patch16 |

## 当前选型

| 属性 | 值 |
|------|-----|
| 模型 | `chinese-clip-vit-base-patch16` |
| 视觉编码器 | ViT-B/16 |
| 文本编码器 | RoBERTa-wwm-ext-base-chinese |
| 格式 | ONNX FP32，双塔独立 |
| 运行时 | ONNX Runtime Mobile v1.24.2 |

## 核心参数

### Embedding

| 参数 | 值 | 来源 |
|------|----|------|
| embedding 维度 | **512** | `ViT-B-16.json` |
| logit_scale | ln(1/0.07) ≈ 2.6593 | `model.py` |

### 图像塔

| 参数 | 值 |
|------|-----|
| 输入尺寸 | 224 × 224 |
| 通道顺序 | RGB, CHW |
| Resize 插值 | Bicubic |
| Normalize mean | `[0.48145466, 0.4578275, 0.40821073]` |
| Normalize std | `[0.26862954, 0.26130258, 0.27577711]` |
| ONNX 输入 | `[B, 3, 224, 224]`, float32 |
| ONNX 输出 | `[B, 512]`, float32 |

### 文本塔

| 参数 | 值 |
|------|-----|
| Tokenizer | Bert WordPiece |
| context_length | 52（含 [CLS]/[SEP]） |
| vocab 大小 | 21128 |
| ONNX 输入 | `[B, 52]`, int64 |
| ONNX 输出 | `[B, 512]`, float32 |

## Tokenizer 流程

1. **BasicTokenizer**
   - CJK 字符逐字拆分
   - 全角转半角，转小写
   - 按空白和标点切分
2. **WordpieceTokenizer**
   - `##` 前缀子词匹配
   - 未知 token 映射为 `[UNK]`
3. **编码**
   - `[CLS]` (101) + tokens + `[SEP]` (102)
   - 截断到 52，不足用 `[PAD]` (0) 填充

## 其他模型变体

| 模型 | embed_dim | image_size | 备注 |
|------|-----------|-----------|------|
| **ViT-B-16（当前）** | **512** | 224 | 12 层 ViT |
| ViT-L-14 | 768 | 224 | 24 层 ViT |
| ViT-L-14-336 | 768 | 336 | 高分辨率 |
| ViT-H-14 | 1024 | 224 | 32 层 ViT |
