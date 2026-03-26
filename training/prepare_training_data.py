#!/usr/bin/env python3
"""
AutoSuggest Training Data Preparation

Converts exported AutoSuggest JSONL training data into formats suitable
for fine-tuning with Unsloth (CUDA) or mlx-lm (Apple Silicon).

Usage:
    python prepare_training_data.py input.jsonl --output-dir ./data
    python prepare_training_data.py input.jsonl --format chatml --model qwen2.5
    python prepare_training_data.py input.jsonl --format alpaca --model llama3
"""

import argparse
import json
import random
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Prompt templates — must match what AutoSuggest sends at inference time
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = (
    "You are an autocomplete engine. Complete the user's text naturally. "
    "Only output the completion, nothing else."
)

# Model-family → chat template mapping
MODEL_TEMPLATES: dict[str, str] = {
    "qwen2.5": "chatml",
    "qwen2": "chatml",
    "qwen": "chatml",
    "llama3": "llama3",
    "llama3.1": "llama3",
    "llama3.2": "llama3",
    "mistral": "mistral",
    "phi3": "chatml",
    "gemma": "gemma",
    "custom": "chatml",  # safe default
}


def format_chatml(prompt: str, completion: str) -> dict[str, Any]:
    """ChatML format — used by Qwen 2.5, Phi-3, and many others."""
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
            {"role": "assistant", "content": completion},
        ]
    }


def format_llama3(prompt: str, completion: str) -> dict[str, Any]:
    """Llama 3 chat format."""
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
            {"role": "assistant", "content": completion},
        ]
    }


def format_alpaca(prompt: str, completion: str) -> dict[str, Any]:
    """Alpaca instruction format — universal fallback."""
    return {
        "instruction": SYSTEM_PROMPT,
        "input": prompt,
        "output": completion,
    }


def format_completion_only(prompt: str, completion: str) -> dict[str, Any]:
    """Raw completion format for causal LM training without chat template."""
    return {"text": f"{prompt}{completion}"}


FORMATTERS = {
    "chatml": format_chatml,
    "llama3": format_llama3,
    "alpaca": format_alpaca,
    "completion": format_completion_only,
}


# ---------------------------------------------------------------------------
# Validation & statistics
# ---------------------------------------------------------------------------


def validate_pair(pair: dict[str, Any]) -> str | None:
    """Returns error string if pair is invalid, None if OK."""
    if "prompt" not in pair or "completion" not in pair:
        return "missing prompt or completion field"
    if not pair["prompt"].strip():
        return "empty prompt"
    if not pair["completion"].strip():
        return "empty completion"
    if len(pair["prompt"]) < 2:
        return "prompt too short (<2 chars)"
    return None


def compute_stats(pairs: list[dict[str, Any]]) -> dict[str, Any]:
    """Compute dataset statistics."""
    prompt_lens = [len(p["prompt"]) for p in pairs]
    completion_lens = [len(p["completion"]) for p in pairs]
    return {
        "total_pairs": len(pairs),
        "avg_prompt_len": sum(prompt_lens) / max(len(prompt_lens), 1),
        "avg_completion_len": sum(completion_lens) / max(len(completion_lens), 1),
        "max_prompt_len": max(prompt_lens, default=0),
        "max_completion_len": max(completion_lens, default=0),
        "total_chars": sum(prompt_lens) + sum(completion_lens),
    }


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    """Load and parse JSONL file, skipping invalid lines."""
    pairs = []
    skipped = 0
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                print(f"  Warning: skipping malformed JSON on line {line_num}")
                skipped += 1
                continue

            error = validate_pair(obj)
            if error:
                print(f"  Warning: skipping line {line_num}: {error}")
                skipped += 1
                continue

            pairs.append(obj)

    if skipped:
        print(f"  Skipped {skipped} invalid lines")
    return pairs


def split_dataset(
    pairs: list[dict[str, Any]], val_ratio: float, seed: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Shuffle and split into train/val."""
    shuffled = pairs.copy()
    random.seed(seed)
    random.shuffle(shuffled)
    split_idx = max(1, int(len(shuffled) * (1 - val_ratio)))
    return shuffled[:split_idx], shuffled[split_idx:]


def write_jsonl(data: list[dict[str, Any]], path: Path) -> None:
    """Write list of dicts as JSONL."""
    with open(path, "w", encoding="utf-8") as f:
        for item in data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")


def resolve_format(fmt: str | None, model: str) -> str:
    """Resolve format from explicit arg or model family."""
    if fmt:
        return fmt
    model_lower = model.lower().replace("-", "").replace("_", "").replace(" ", "")
    for key, template in MODEL_TEMPLATES.items():
        if key in model_lower:
            return template
    print(f"  Unknown model family '{model}', defaulting to ChatML format")
    return "chatml"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare AutoSuggest training data for fine-tuning",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage (Qwen 2.5, ChatML format)
  python prepare_training_data.py ~/Library/Application\\ Support/AutoSuggestApp/TrainingData/training-pairs.jsonl

  # For Llama 3
  python prepare_training_data.py data.jsonl --model llama3 --output-dir ./data

  # Custom format
  python prepare_training_data.py data.jsonl --format alpaca

  # Larger validation split
  python prepare_training_data.py data.jsonl --val-ratio 0.2
        """,
    )
    parser.add_argument("input", type=Path, help="Path to AutoSuggest JSONL export")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("./data"),
        help="Output directory (default: ./data)",
    )
    parser.add_argument(
        "--model",
        default="qwen2.5",
        help="Model family for prompt template (default: qwen2.5)",
    )
    parser.add_argument(
        "--format",
        choices=list(FORMATTERS.keys()),
        default=None,
        help="Override output format (auto-detected from --model if omitted)",
    )
    parser.add_argument(
        "--val-ratio",
        type=float,
        default=0.1,
        help="Validation split ratio (default: 0.1)",
    )
    parser.add_argument(
        "--seed", type=int, default=42, help="Random seed for shuffle (default: 42)"
    )
    parser.add_argument(
        "--min-pairs",
        type=int,
        default=10,
        help="Minimum pairs required (default: 10)",
    )

    args = parser.parse_args()

    # Validate input
    if not args.input.exists():
        print(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    print(f"Loading training data from {args.input}...")
    pairs = load_jsonl(args.input)

    if len(pairs) < args.min_pairs:
        print(
            f"Error: Only {len(pairs)} valid pairs found (minimum: {args.min_pairs})."
        )
        print("Collect more training data in AutoSuggest before fine-tuning.")
        sys.exit(1)

    if len(pairs) < 100:
        print(
            f"  Warning: Only {len(pairs)} pairs. Fine-tuning works best with 500+ pairs."
        )
        print("  Consider collecting more data for better results.\n")

    # Stats
    stats = compute_stats(pairs)
    print(f"\nDataset statistics:")
    print(f"  Total pairs:          {stats['total_pairs']}")
    print(f"  Avg prompt length:    {stats['avg_prompt_len']:.0f} chars")
    print(f"  Avg completion length: {stats['avg_completion_len']:.0f} chars")
    print(f"  Total characters:     {stats['total_chars']:,}")

    # Resolve format
    fmt = resolve_format(args.format, args.model)
    formatter = FORMATTERS[fmt]
    print(f"\nUsing format: {fmt} (model: {args.model})")

    # Format pairs
    formatted = [formatter(p["prompt"], p["completion"]) for p in pairs]

    # Split
    train_data, val_data = split_dataset(formatted, args.val_ratio, args.seed)
    print(f"Split: {len(train_data)} train / {len(val_data)} validation")

    # Write output
    args.output_dir.mkdir(parents=True, exist_ok=True)
    train_path = args.output_dir / "train.jsonl"
    val_path = args.output_dir / "val.jsonl"
    stats_path = args.output_dir / "stats.json"

    write_jsonl(train_data, train_path)
    write_jsonl(val_data, val_path)

    # Save stats + config for reproducibility
    meta = {
        "source": str(args.input),
        "model": args.model,
        "format": fmt,
        "val_ratio": args.val_ratio,
        "seed": args.seed,
        "stats": stats,
        "train_count": len(train_data),
        "val_count": len(val_data),
    }
    with open(stats_path, "w") as f:
        json.dump(meta, f, indent=2)

    print(f"\nOutput written to {args.output_dir}/")
    print(f"  {train_path}")
    print(f"  {val_path}")
    print(f"  {stats_path}")
    print(f"\nNext steps:")
    print(f"  # Fine-tune with Unsloth (CUDA GPU / Colab):")
    print(f"  python finetune.py --data-dir {args.output_dir}")
    print(f"")
    print(f"  # Fine-tune with MLX (Apple Silicon Mac):")
    print(f"  python finetune_mlx.py --data-dir {args.output_dir}")


if __name__ == "__main__":
    main()
