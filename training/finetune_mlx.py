#!/usr/bin/env python3
"""
AutoSuggest Fine-Tuning with MLX (Apple Silicon)

Fine-tunes a language model on your AutoSuggest training data using
Apple's MLX framework. Runs natively on any M-series Mac — no CUDA needed.

Prerequisites:
    pip install -r requirements-mlx.txt

Usage:
    # Default: Qwen 2.5 1.5B
    python finetune_mlx.py --data-dir ./data

    # Qwen 2.5 3B
    python finetune_mlx.py --data-dir ./data --preset qwen2.5-3b

    # Llama 3.2 1B
    python finetune_mlx.py --data-dir ./data --preset llama3.2-1b

    # Custom model
    python finetune_mlx.py --data-dir ./data --model Qwen/Qwen2.5-1.5B-Instruct

    # Export existing adapter to GGUF
    python finetune_mlx.py --data-dir ./data --export-only --adapter-path ./output-mlx/adapters
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Model presets
# ---------------------------------------------------------------------------

MODEL_PRESETS = {
    "qwen2.5-0.5b": {
        "hf_id": "Qwen/Qwen2.5-0.5B-Instruct",
        "ollama_base": "qwen2.5:0.5b",
        "min_ram_gb": 4,
    },
    "qwen2.5-1.5b": {
        "hf_id": "Qwen/Qwen2.5-1.5B-Instruct",
        "ollama_base": "qwen2.5:1.5b",
        "min_ram_gb": 8,
    },
    "qwen2.5-3b": {
        "hf_id": "Qwen/Qwen2.5-3B-Instruct",
        "ollama_base": "qwen2.5:3b",
        "min_ram_gb": 16,
    },
    "qwen2.5-7b": {
        "hf_id": "Qwen/Qwen2.5-7B-Instruct",
        "ollama_base": "qwen2.5:7b",
        "min_ram_gb": 24,
    },
    "llama3.2-1b": {
        "hf_id": "meta-llama/Llama-3.2-1B-Instruct",
        "ollama_base": "llama3.2:1b",
        "min_ram_gb": 8,
    },
    "llama3.2-3b": {
        "hf_id": "meta-llama/Llama-3.2-3B-Instruct",
        "ollama_base": "llama3.2:3b",
        "min_ram_gb": 16,
    },
}

DEFAULT_PRESET = "qwen2.5-1.5b"


# ---------------------------------------------------------------------------
# System RAM check
# ---------------------------------------------------------------------------


def get_system_ram_gb() -> float:
    """Get total system RAM in GB (unified memory on Apple Silicon)."""
    try:
        import os
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / (1024**3)
    except Exception:
        return 0


def check_ram(preset_name: str) -> None:
    """Warn if system RAM is below minimum for chosen preset."""
    preset = MODEL_PRESETS.get(preset_name)
    if not preset:
        return
    ram_gb = get_system_ram_gb()
    if ram_gb > 0 and ram_gb < preset["min_ram_gb"]:
        print(f"  Warning: {preset_name} recommends {preset['min_ram_gb']}GB+ RAM.")
        print(f"  Your system has ~{ram_gb:.0f}GB. Training may be slow or fail.")
        print(f"  Consider a smaller model (e.g., qwen2.5-0.5b).\n")


# ---------------------------------------------------------------------------
# Training with mlx-lm
# ---------------------------------------------------------------------------


def create_lora_config(args: argparse.Namespace, output_dir: Path) -> Path:
    """Create mlx-lm LoRA configuration file."""
    config = {
        "lora_layers": args.lora_layers,
        "lora_parameters": {
            "rank": args.lora_r,
            "alpha": args.lora_alpha,
            "dropout": args.lora_dropout,
            "scale": args.lora_alpha / args.lora_r,
        },
        "learning_rate": args.learning_rate,
        "batch_size": args.batch_size,
        "iters": args.iters,
        "val_batches": 25,
        "steps_per_report": 10,
        "steps_per_eval": 100,
        "save_every": 200,
        "adapter_path": str(output_dir / "adapters"),
        "max_seq_length": args.max_seq_length,
        "grad_checkpoint": args.grad_checkpoint,
    }

    config_path = output_dir / "lora_config.yaml"

    # Write as YAML-like (mlx-lm accepts JSON too)
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

    return config_path


def train(args: argparse.Namespace) -> Path:
    """Run LoRA fine-tuning with mlx-lm."""
    preset = MODEL_PRESETS.get(args.preset)
    model_id = preset["hf_id"] if preset else args.model

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    data_dir = Path(args.data_dir)
    train_path = data_dir / "train.jsonl"

    if not train_path.exists():
        print(f"Error: {train_path} not found. Run prepare_training_data.py first.")
        sys.exit(1)

    # Check RAM
    if args.preset:
        check_ram(args.preset)

    print(f"Model: {model_id}")
    print(f"Data:  {data_dir}")

    # Auto-calculate iterations if not set
    if args.iters == 0:
        # Count lines
        with open(train_path) as f:
            num_samples = sum(1 for _ in f)
        # ~3 epochs worth
        args.iters = max(100, (num_samples * args.epochs) // args.batch_size)
        print(f"Auto-calculated iterations: {args.iters} (~{args.epochs} epochs)")

    adapter_path = output_dir / "adapters"
    adapter_path.mkdir(parents=True, exist_ok=True)

    # Build mlx_lm.lora command
    cmd = [
        sys.executable, "-m", "mlx_lm.lora",
        "--model", model_id,
        "--train",
        "--data", str(data_dir),
        "--adapter-path", str(adapter_path),
        "--batch-size", str(args.batch_size),
        "--lora-layers", str(args.lora_layers),
        "--iters", str(args.iters),
        "--learning-rate", str(args.learning_rate),
        "--steps-per-report", "10",
        "--steps-per-eval", "100",
        "--save-every", "200",
    ]

    if args.grad_checkpoint:
        cmd.append("--grad-checkpoint")

    print(f"\nRunning: {' '.join(cmd)}\n")
    print("-" * 60)

    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"\nTraining failed with exit code {result.returncode}")
        sys.exit(1)

    print("-" * 60)
    print(f"\nLoRA adapter saved to {adapter_path}")
    return adapter_path


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def fuse_and_export(args: argparse.Namespace, adapter_path: Path) -> Path:
    """Fuse LoRA adapter into base model and optionally convert to GGUF."""
    preset = MODEL_PRESETS.get(args.preset)
    model_id = preset["hf_id"] if preset else args.model

    output_dir = Path(args.output_dir)
    fused_dir = output_dir / "fused-model"

    print(f"\nFusing adapter with base model...")

    # Fuse adapter into model
    cmd_fuse = [
        sys.executable, "-m", "mlx_lm.fuse",
        "--model", model_id,
        "--adapter-path", str(adapter_path),
        "--save-path", str(fused_dir),
    ]

    result = subprocess.run(cmd_fuse)
    if result.returncode != 0:
        print("Fuse failed. You can still use the adapter with mlx-lm directly.")
        return adapter_path

    print(f"Fused model saved to {fused_dir}")

    # Convert to GGUF if requested
    if not args.skip_gguf:
        gguf_path = export_gguf(args, fused_dir)
        if gguf_path:
            create_ollama_modelfile(args, gguf_path)
            return gguf_path

    return fused_dir


def export_gguf(args: argparse.Namespace, fused_dir: Path) -> Path | None:
    """Convert fused MLX model to GGUF using mlx-lm or llama.cpp converter."""
    output_dir = Path(args.output_dir)
    gguf_dir = output_dir / "gguf"
    gguf_dir.mkdir(parents=True, exist_ok=True)

    model_name = args.ollama_name or "autosuggest-finetuned"
    gguf_path = gguf_dir / f"{model_name}-{args.quantization}.gguf"

    print(f"\nConverting to GGUF ({args.quantization})...")

    # Try mlx-lm's built-in GGUF conversion
    cmd = [
        sys.executable, "-m", "mlx_lm.convert",
        "--hf-path", str(fused_dir),
        "--mlx-path", str(gguf_dir / "mlx-tmp"),
        "--quantize",
    ]

    # mlx-lm convert doesn't directly output GGUF, so we use a different approach
    # Use the HuggingFace-to-GGUF converter if available
    try:
        # Try using llama-cpp-python's converter
        from huggingface_hub import snapshot_download
        convert_cmd = [
            sys.executable, "-m", "llama_cpp.llama_convert",
            "--outfile", str(gguf_path),
            "--outtype", args.quantization,
            str(fused_dir),
        ]
        result = subprocess.run(convert_cmd, capture_output=True)
        if result.returncode == 0:
            print(f"GGUF model saved to {gguf_path}")
            return gguf_path
    except ImportError:
        pass

    # Fallback: instruct user to convert manually
    print("\nAutomatic GGUF conversion not available.")
    print("To convert manually, install llama.cpp and run:")
    print(f"  python llama.cpp/convert_hf_to_gguf.py {fused_dir} --outfile {gguf_path} --outtype {args.quantization}")
    print(f"\nOr use the fused model directly with mlx-lm:")
    print(f"  python -m mlx_lm.generate --model {fused_dir} --prompt 'Hello'")

    return None


def create_ollama_modelfile(args: argparse.Namespace, gguf_path: Path) -> Path:
    """Generate an Ollama Modelfile."""
    output_dir = Path(args.output_dir)
    modelfile_path = output_dir / "Modelfile"

    system_prompt = (
        "You are an autocomplete engine. Complete the user's text naturally. "
        "Only output the completion, nothing else."
    )

    content = f"""# AutoSuggest Fine-Tuned Model (MLX trained)
# Created from AutoSuggest training data on Apple Silicon
#
# Usage:
#   ollama create autosuggest-finetuned -f Modelfile

FROM {gguf_path.name}

PARAMETER temperature 0.3
PARAMETER top_p 0.9
PARAMETER repeat_penalty 1.1
PARAMETER stop "<|endoftext|>"
PARAMETER stop "<|im_end|>"
PARAMETER num_predict 128

SYSTEM \"\"\"{system_prompt}\"\"\"
"""

    with open(modelfile_path, "w") as f:
        f.write(content)

    model_name = args.ollama_name or "autosuggest-finetuned"
    print(f"\nOllama Modelfile saved to {modelfile_path}")
    print(f"\nTo import into Ollama:")
    print(f"  cd {output_dir}")
    print(f"  cp {gguf_path} {output_dir}/")
    print(f"  ollama create {model_name} -f Modelfile")
    print(f"\nThen in AutoSuggest settings, set model to: {model_name}")

    return modelfile_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Fine-tune a model on AutoSuggest data using MLX (Apple Silicon)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Model presets (use with --preset):
  qwen2.5-0.5b    Qwen 2.5 0.5B Instruct  (4GB+ RAM)
  qwen2.5-1.5b    Qwen 2.5 1.5B Instruct  (8GB+ RAM)  [DEFAULT]
  qwen2.5-3b      Qwen 2.5 3B Instruct    (16GB+ RAM)
  qwen2.5-7b      Qwen 2.5 7B Instruct    (24GB+ RAM)
  llama3.2-1b     Llama 3.2 1B Instruct   (8GB+ RAM)
  llama3.2-3b     Llama 3.2 3B Instruct   (16GB+ RAM)

Examples:
  # Train on Apple Silicon (M1/M2/M3/M4)
  python finetune_mlx.py --data-dir ./data

  # Larger model
  python finetune_mlx.py --data-dir ./data --preset qwen2.5-3b

  # More training iterations
  python finetune_mlx.py --data-dir ./data --iters 1000

  # Export existing adapter
  python finetune_mlx.py --data-dir ./data --export-only --adapter-path ./output-mlx/adapters
        """,
    )

    # Data
    parser.add_argument(
        "--data-dir", type=str, default="./data", help="Directory with train.jsonl/val.jsonl"
    )
    parser.add_argument(
        "--output-dir", type=str, default="./output-mlx", help="Output directory"
    )

    # Model
    parser.add_argument(
        "--preset",
        choices=list(MODEL_PRESETS.keys()),
        default=DEFAULT_PRESET,
        help=f"Model preset (default: {DEFAULT_PRESET})",
    )
    parser.add_argument(
        "--model", type=str, default=None, help="Custom HuggingFace model ID"
    )
    parser.add_argument(
        "--max-seq-length", type=int, default=2048, help="Max sequence length"
    )

    # LoRA
    parser.add_argument("--lora-r", type=int, default=16, help="LoRA rank (default: 16)")
    parser.add_argument("--lora-alpha", type=float, default=32.0, help="LoRA alpha (default: 32)")
    parser.add_argument(
        "--lora-dropout", type=float, default=0.05, help="LoRA dropout (default: 0.05)"
    )
    parser.add_argument(
        "--lora-layers", type=int, default=16, help="Number of LoRA layers (default: 16)"
    )

    # Training
    parser.add_argument("--epochs", type=int, default=3, help="Epochs for auto-iter calc")
    parser.add_argument(
        "--iters", type=int, default=0, help="Training iterations (0=auto from epochs)"
    )
    parser.add_argument(
        "--learning-rate", type=float, default=1e-4, help="Learning rate (default: 1e-4)"
    )
    parser.add_argument("--batch-size", type=int, default=4, help="Batch size (default: 4)")
    parser.add_argument(
        "--grad-checkpoint", action="store_true", help="Enable gradient checkpointing (saves RAM)"
    )

    # Export
    parser.add_argument(
        "--quantization", default="q4_k_m", help="GGUF quantization (default: q4_k_m)"
    )
    parser.add_argument(
        "--ollama-name", default="autosuggest-finetuned", help="Ollama model name"
    )
    parser.add_argument("--skip-gguf", action="store_true", help="Skip GGUF conversion")

    # Modes
    parser.add_argument("--export-only", action="store_true", help="Skip training, export only")
    parser.add_argument("--adapter-path", type=str, default=None, help="Existing adapter path")

    args = parser.parse_args()

    if args.model:
        args.preset = None

    print("=" * 60)
    print("  AutoSuggest Fine-Tuning (MLX — Apple Silicon)")
    print("=" * 60)

    # Check we're on Apple Silicon
    import platform
    if platform.machine() != "arm64":
        print("Warning: MLX requires Apple Silicon (M1/M2/M3/M4).")
        print("For Intel/NVIDIA, use finetune.py (Unsloth) instead.")
        sys.exit(1)

    if args.export_only:
        adapter_path = Path(args.adapter_path or f"{args.output_dir}/adapters")
        if not adapter_path.exists():
            print(f"Error: Adapter not found at {adapter_path}")
            sys.exit(1)
    else:
        adapter_path = train(args)

    fuse_and_export(args, adapter_path)
    print("\nDone!")


if __name__ == "__main__":
    main()
