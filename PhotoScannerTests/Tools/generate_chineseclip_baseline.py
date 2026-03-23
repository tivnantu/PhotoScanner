#!/usr/bin/env python3
"""Generate ChineseCLIP baseline.json from fixed fixtures.

Run with `cd PhotoScannerTests/Tools && uv run generate_chineseclip_baseline.py`.
This uses uv's default virtual environment at `PhotoScannerTests/Tools/.venv`.

This script reads `baseline_seed.json`, runs the current ONNX model on the
configured image/text samples, and writes a generated `baseline.json` that can
be consumed by iOS-side validation helpers.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any

try:
    import numpy as np
except ImportError as exc:  # pragma: no cover
    raise SystemExit("缺少依赖 numpy，请先安装后再运行脚本。") from exc

try:
    import onnxruntime as ort
except ImportError as exc:  # pragma: no cover
    raise SystemExit("缺少依赖 onnxruntime，请先安装后再运行脚本。") from exc

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    raise SystemExit("缺少依赖 Pillow，请先安装后再运行脚本。") from exc


@dataclass(frozen=True)
class ModelPaths:
    image_encoder: Path
    text_encoder: Path
    vocab: Path


@dataclass(frozen=True)
class GenerationContext:
    project_root: Path
    fixture_root: Path
    chinese_clip_repo_root: Path
    image_size: int
    context_length: int
    image_mean: list[float]
    image_std: list[float]
    model_paths: ModelPaths


REQUIRED_SPECIAL_TOKEN_IDS = {
    "[PAD]": 0,
    "[UNK]": 100,
    "[CLS]": 101,
    "[SEP]": 102,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成 ChineseCLIP baseline.json")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="PhotoScanner 工程根目录",
    )
    parser.add_argument(
        "--seed",
        type=Path,
        default=None,
        help="baseline_seed.json 路径，默认使用 PhotoScannerTests/Baseline/ChineseCLIP/baseline_seed.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="生成的 baseline.json 路径，默认写入 seed 同目录",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def resolve_context(project_root: Path, seed_path: Path, seed: dict[str, Any]) -> GenerationContext:
    model = seed["model"]
    paths = model["paths"]
    fixture_root = seed_path.parent

    return GenerationContext(
        project_root=project_root,
        fixture_root=fixture_root,
        chinese_clip_repo_root=project_root.parent / "Chinese-CLIP",
        image_size=int(model["image_size"]),
        context_length=int(model["context_length"]),
        image_mean=[float(value) for value in model["image_mean"]],
        image_std=[float(value) for value in model["image_std"]],
        model_paths=ModelPaths(
            image_encoder=project_root / paths["image_encoder"],
            text_encoder=project_root / paths["text_encoder"],
            vocab=project_root / paths["vocab"],
        ),
    )


def ensure_paths_exist(context: GenerationContext) -> None:
    tokenizer_module = context.chinese_clip_repo_root / "cn_clip/clip/bert_tokenizer.py"
    for path in [
        context.model_paths.image_encoder,
        context.model_paths.text_encoder,
        context.model_paths.vocab,
        context.chinese_clip_repo_root,
        tokenizer_module,
    ]:
        if not path.exists():
            raise SystemExit(f"模型、词表或 Chinese-CLIP 仓库不存在: {path}")


@lru_cache(maxsize=1)
def load_official_tokenizer_module(module_path_str: str) -> Any:
    module_path = Path(module_path_str)
    spec = importlib.util.spec_from_file_location(
        "photoscanner_chineseclip_bert_tokenizer",
        module_path,
    )
    if spec is None or spec.loader is None:
        raise SystemExit(f"无法加载官方 tokenizer 模块: {module_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def create_tokenizer(context: GenerationContext) -> Any:
    tokenizer_module_path = context.chinese_clip_repo_root / "cn_clip/clip/bert_tokenizer.py"
    module = load_official_tokenizer_module(str(tokenizer_module_path))
    full_tokenizer_class = getattr(module, "FullTokenizer", None)
    if full_tokenizer_class is None:
        raise SystemExit(f"官方 tokenizer 模块缺少 FullTokenizer: {tokenizer_module_path}")

    tokenizer = full_tokenizer_class(vocab_file=str(context.model_paths.vocab), do_lower_case=True)
    for token, expected_id in REQUIRED_SPECIAL_TOKEN_IDS.items():
        actual_id = tokenizer.vocab.get(token)
        if actual_id != expected_id:
            raise SystemExit(
                f"词表特殊 token id 异常: token={token}, expected={expected_id}, actual={actual_id}"
            )
    return tokenizer


def create_session(model_path: Path) -> ort.InferenceSession:
    return ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])


def preprocess_image(image_path: Path, image_size: int, mean: list[float], std: list[float]) -> np.ndarray:
    with Image.open(image_path) as image:
        rgb_image = image.convert("RGB")
        resized = rgb_image.resize((image_size, image_size), resample=Image.Resampling.BICUBIC)
        np_image = np.asarray(resized, dtype=np.float32) / 255.0

    chw = np.transpose(np_image, (2, 0, 1))
    mean_array = np.asarray(mean, dtype=np.float32).reshape(3, 1, 1)
    std_array = np.asarray(std, dtype=np.float32).reshape(3, 1, 1)
    normalized = (chw - mean_array) / std_array
    return normalized[np.newaxis, ...].astype(np.float32)


def normalize_embedding(vector: np.ndarray) -> np.ndarray:
    vector = vector.astype(np.float32)
    norm = float(np.linalg.norm(vector))
    if not np.isfinite(norm) or norm <= np.finfo(np.float32).eps:
        raise SystemExit("生成基线失败：embedding 范数异常")
    return vector / norm


def encode_text(tokenizer: Any, text: str, context_length: int) -> list[int]:
    content_token_ids = tokenizer.convert_tokens_to_ids(tokenizer.tokenize(text))
    max_content_length = context_length - 2
    truncated_content = [int(token_id) for token_id in content_token_ids[:max_content_length]]

    token_ids = [
        REQUIRED_SPECIAL_TOKEN_IDS["[CLS]"],
        *truncated_content,
        REQUIRED_SPECIAL_TOKEN_IDS["[SEP]"],
    ]
    token_ids.extend([REQUIRED_SPECIAL_TOKEN_IDS["[PAD]"]] * (context_length - len(token_ids)))

    if len(token_ids) != context_length:
        raise SystemExit(f"文本编码长度异常: {text} -> {len(token_ids)}")
    return token_ids


def run_text_embedding(session: ort.InferenceSession, token_ids: list[int]) -> np.ndarray:
    output_name = session.get_outputs()[0].name
    input_name = session.get_inputs()[0].name
    array = np.asarray([token_ids], dtype=np.int64)
    result = session.run([output_name], {input_name: array})[0]
    vector = np.asarray(result, dtype=np.float32).reshape(-1)
    return normalize_embedding(vector)


def run_image_embedding(session: ort.InferenceSession, image_tensor: np.ndarray) -> np.ndarray:
    output_name = session.get_outputs()[0].name
    input_name = session.get_inputs()[0].name
    result = session.run([output_name], {input_name: image_tensor})[0]
    vector = np.asarray(result, dtype=np.float32).reshape(-1)
    return normalize_embedding(vector)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))


def write_float32le_binary(path: Path, values: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(np.asarray(values, dtype="<f4").tobytes())


def main() -> None:
    args = parse_args()
    project_root = args.project_root.resolve()
    seed_path = (args.seed or (project_root / "PhotoScannerTests/Baseline/ChineseCLIP/baseline_seed.json")).resolve()
    output_path = (args.output or seed_path.with_name("baseline.json")).resolve()

    seed = load_json(seed_path)
    context = resolve_context(project_root, seed_path, seed)
    ensure_paths_exist(context)

    tokenizer = create_tokenizer(context)
    image_session = create_session(context.model_paths.image_encoder)
    text_session = create_session(context.model_paths.text_encoder)

    text_cases_output: list[dict[str, Any]] = []
    image_cases_output: list[dict[str, Any]] = []
    similarity_cases_output: list[dict[str, Any]] = []

    text_embeddings: dict[str, np.ndarray] = {}
    image_embeddings: dict[str, np.ndarray] = {}

    for text_case in seed["text_cases"]:
        text = text_case["text"]
        token_ids = encode_text(tokenizer, text, context.context_length)
        embedding = run_text_embedding(text_session, token_ids)
        text_embeddings[text_case["id"]] = embedding
        text_cases_output.append(
            {
                "id": text_case["id"],
                "text": text,
                "token_ids": token_ids,
                "text_embedding": [round(float(value), 8) for value in embedding.tolist()],
            }
        )

    for image_case in seed["image_cases"]:
        relative_image_path = Path(image_case["image"])
        image_path = context.fixture_root / relative_image_path
        if not image_path.exists():
            raise SystemExit(f"基线图片不存在: {image_path}")

        image_tensor = preprocess_image(
            image_path=image_path,
            image_size=context.image_size,
            mean=context.image_mean,
            std=context.image_std,
        )
        preprocessed_tensor = np.asarray(image_tensor[0], dtype=np.float32)
        preprocessed_tensor_relative_path = Path("preprocessed") / f"{image_case['id']}.f32le.bin"
        write_float32le_binary(output_path.parent / preprocessed_tensor_relative_path, preprocessed_tensor)

        embedding = run_image_embedding(image_session, image_tensor)
        image_embeddings[image_case["id"]] = embedding
        image_cases_output.append(
            {
                "id": image_case["id"],
                "image": image_case["image"],
                "preprocessed_tensor_file": preprocessed_tensor_relative_path.as_posix(),
                "preprocessed_tensor_shape": [3, context.image_size, context.image_size],
                "image_embedding": [round(float(value), 8) for value in embedding.tolist()],
            }
        )

    for pair in seed["similarity_pairs"]:
        image_embedding = image_embeddings[pair["image_case_id"]]
        text_embedding = text_embeddings[pair["text_case_id"]]
        similarity_cases_output.append(
            {
                "id": pair["id"],
                "image_case_id": pair["image_case_id"],
                "text_case_id": pair["text_case_id"],
                "similarity": round(cosine_similarity(image_embedding, text_embedding), 8),
            }
        )

    generated = {
        "baseline_version": seed["baseline_version"],
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator": {
            "name": "generate_chineseclip_baseline.py",
            "onnxruntime_version": ort.__version__,
        },
        "model": seed["model"],
        "tolerances": seed["tolerances"],
        "text_cases": text_cases_output,
        "image_cases": image_cases_output,
        "similarity_cases": similarity_cases_output,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as file:
        json.dump(generated, file, ensure_ascii=False, indent=2)
        file.write("\n")

    print(f"已生成 baseline: {output_path}")


if __name__ == "__main__":
    main()
