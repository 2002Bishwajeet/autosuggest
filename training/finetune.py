#!/usr/bin/env python3
"""
AutoSuggest Fine-Tuning with Unsloth (CUDA GPU / Google Colab)

Fine-tunes a language model on your AutoSuggest training data using
Unsloth for 2-5x faster training with 60% less memory.

Prerequisites:
    pip install -r requirements.txt

Usage:
    # Default: Qwen 2.5 1.5B
    python finetune.py --data-dir ./data

    # Qwen 2.5 3B with custom settings
    python finetune.py --data-dir ./data --model unsloth/Qwen2.5-3B --epochs 5

    # Llama 3.2 1B
    python finetune.py --data-dir ./data --model unsloth/Llama-3.2-1B-Instruct

    # Export only (skip training, use existing adapter)
    python finetune.py --data-dir ./data --export-only --adapter-path ./output/adapter
"""

import argparse
import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Model presets
# ---------------------------------------------------------------------------

MODEL_PRESETS = {
    "qwen2.5-0.5b": {
        "hf_id": "unsloth/Qwen2.5-0.5B-Instruct",
        "max_seq_length": 2048,
        "ollama_base": "qwen2.5:0.5b",
    },
    "qwen2.5-1.5b": {
        "hf_id": "unsloth/Qwen2.5-1.5B-Instruct",
        "max_seq_length": 2048,
        "ollama_base": "qwen2.5:1.5b",
    },
    "qwen2.5-3b": {
        "hf_id": "unsloth/Qwen2.5-3B-Instruct",
        "max_seq_length": 2048,
        "ollama_base": "qwen2.5:3b",
    },
    "qwen2.5-7b": {
        "hf_id": "unsloth/Qwen2.5-7B-Instruct",
        "max_seq_length": 4096,
        "ollama_base": "qwen2.5:7b",
    },
    "llama3.2-1b": {
        "hf_id": "unsloth/Llama-3.2-1B-Instruct",
        "max_seq_length": 2048,
        "ollama_base": "llama3.2:1b",
    },
    "llama3.2-3b": {
        "hf_id": "unsloth/Llama-3.2-3B-Instruct",
        "max_seq_length": 2048,
        "ollama_base": "llama3.2:3b",
    },
}

DEFAULT_PRESET = "qwen2.5-1.5b"

# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------


def train(args: argparse.Namespace) -> Path:
    """Run LoRA fine-tuning with Unsloth."""
    # Import here so --help works without CUDA
    from unsloth import FastLanguageModel
    from trl import SFTTrainer
    from transformers import TrainingArguments
    from datasets import load_dataset

    # Resolve model
    preset = MODEL_PRESETS.get(args.preset)
    model_id = preset["hf_id"] if preset else args.model
    max_seq_length = preset["max_seq_length"] if preset else args.max_seq_length

    print(f"Loading model: {model_id}")
    print(f"Max sequence length: {max_seq_length}")

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=model_id,
        max_seq_length=max_seq_length,
        dtype=None,  # auto-detect
        load_in_4bit=args.load_in_4bit,
    )

    # Apply LoRA
    model = FastLanguageModel.get_peft_model(
        model,
        r=args.lora_r,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=42,
    )

    # Load data
    data_dir = Path(args.data_dir)
    train_path = data_dir / "train.jsonl"
    val_path = data_dir / "val.jsonl"

    if not train_path.exists():
        print(f"Error: {train_path} not found. Run prepare_training_data.py first.")
        sys.exit(1)

    dataset = load_dataset(
        "json",
        data_files={
            "train": str(train_path),
            "validation": str(val_path) if val_path.exists() else str(train_path),
        },
    )

    print(f"Training samples: {len(dataset['train'])}")
    print(f"Validation samples: {len(dataset['validation'])}")

    # Detect format and apply chat template
    sample = dataset["train"][0]
    if "messages" in sample:
        # Chat format — apply tokenizer chat template
        def apply_chat_template(examples):
            texts = []
            for messages in examples["messages"]:
                text = tokenizer.apply_chat_template(
                    messages, tokenize=False, add_generation_prompt=False
                )
                texts.append(text)
            return {"text": texts}

        dataset = dataset.map(apply_chat_template, batched=True)
    elif "instruction" in sample:
        # Alpaca format
        def format_alpaca(examples):
            texts = []
            for inst, inp, out in zip(
                examples["instruction"], examples["input"], examples["output"]
            ):
                text = f"### Instruction:\n{inst}\n\n### Input:\n{inp}\n\n### Response:\n{out}"
                texts.append(text)
            return {"text": texts}

        dataset = dataset.map(format_alpaca, batched=True)
    # else: assume "text" field already exists

    # Training arguments
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    training_args = TrainingArguments(
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.gradient_accumulation,
        warmup_ratio=0.05,
        num_train_epochs=args.epochs,
        learning_rate=args.learning_rate,
        fp16=not args.bf16,
        bf16=args.bf16,
        logging_steps=10,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="cosine",
        seed=42,
        output_dir=str(output_dir / "checkpoints"),
        save_strategy="epoch",
        eval_strategy="epoch" if val_path.exists() else "no",
        report_to="none",
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset["train"],
        eval_dataset=dataset.get("validation"),
        max_seq_length=max_seq_length,
        dataset_text_field="text",
        args=training_args,
    )

    print("\nStarting training...")
    stats = trainer.train()
    print(f"\nTraining complete! Loss: {stats.training_loss:.4f}")

    # Save adapter
    adapter_path = output_dir / "adapter"
    model.save_pretrained(str(adapter_path))
    tokenizer.save_pretrained(str(adapter_path))
    print(f"LoRA adapter saved to {adapter_path}")

    return adapter_path


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def export_gguf(args: argparse.Namespace, adapter_path: Path) -> Path:
    """Merge adapter and export to GGUF format."""
    from unsloth import FastLanguageModel

    preset = MODEL_PRESETS.get(args.preset)
    model_id = preset["hf_id"] if preset else args.model
    max_seq_length = preset["max_seq_length"] if preset else args.max_seq_length

    print(f"\nLoading model + adapter for GGUF export...")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=str(adapter_path),
        max_seq_length=max_seq_length,
        dtype=None,
        load_in_4bit=False,
    )

    output_dir = Path(args.output_dir)
    gguf_dir = output_dir / "gguf"
    gguf_dir.mkdir(parents=True, exist_ok=True)

    quantization = args.quantization
    print(f"Exporting GGUF with {quantization} quantization...")

    model.save_pretrained_gguf(
        str(gguf_dir),
        tokenizer,
        quantization_method=quantization,
    )

    # Find the generated GGUF file
    gguf_files = list(gguf_dir.glob("*.gguf"))
    if not gguf_files:
        print("Warning: No GGUF file found in output. Check for errors above.")
        return gguf_dir

    gguf_path = gguf_files[0]
    print(f"GGUF model saved to {gguf_path}")
    return gguf_path


def create_ollama_modelfile(args: argparse.Namespace, gguf_path: Path) -> Path:
    """Generate an Ollama Modelfile for the fine-tuned model."""
    preset = MODEL_PRESETS.get(args.preset)
    output_dir = Path(args.output_dir)

    modelfile_path = output_dir / "Modelfile"

    system_prompt = (
        "You are an autocomplete engine. Complete the user's text naturally. "
        "Only output the completion, nothing else."
    )

    content = f"""# AutoSuggest Fine-Tuned Model
# Created from AutoSuggest training data
#
# Usage:
#   ollama create autosuggest-finetuned -f Modelfile
#   Then set "autosuggest-finetuned" as your model in AutoSuggest settings.

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
        description="Fine-tune a model on AutoSuggest training data using Unsloth",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Model presets (use with --preset):
  qwen2.5-0.5b    Qwen 2.5 0.5B Instruct  (4GB+ VRAM)
  qwen2.5-1.5b    Qwen 2.5 1.5B Instruct  (6GB+ VRAM) [DEFAULT]
  qwen2.5-3b      Qwen 2.5 3B Instruct    (8GB+ VRAM)
  qwen2.5-7b      Qwen 2.5 7B Instruct    (16GB+ VRAM)
  llama3.2-1b     Llama 3.2 1B Instruct   (6GB+ VRAM)
  llama3.2-3b     Llama 3.2 3B Instruct   (8GB+ VRAM)

Examples:
  python finetune.py --data-dir ./data
  python finetune.py --data-dir ./data --preset qwen2.5-3b --epochs 5
  python finetune.py --data-dir ./data --model unsloth/Mistral-7B-Instruct-v0.3
  python finetune.py --data-dir ./data --export-only --adapter-path ./output/adapter
        """,
    )

    # Data
    parser.add_argument(
        "--data-dir", type=str, default="./data", help="Directory with train.jsonl/val.jsonl"
    )
    parser.add_argument(
        "--output-dir", type=str, default="./output", help="Output directory"
    )

    # Model selection
    parser.add_argument(
        "--preset",
        choices=list(MODEL_PRESETS.keys()),
        default=DEFAULT_PRESET,
        help=f"Model preset (default: {DEFAULT_PRESET})",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=None,
        help="Custom HuggingFace model ID (overrides --preset)",
    )
    parser.add_argument(
        "--max-seq-length", type=int, default=2048, help="Max sequence length for custom models"
    )

    # LoRA config
    parser.add_argument("--lora-r", type=int, default=16, help="LoRA rank (default: 16)")
    parser.add_argument("--lora-alpha", type=int, default=32, help="LoRA alpha (default: 32)")
    parser.add_argument(
        "--lora-dropout", type=float, default=0.05, help="LoRA dropout (default: 0.05)"
    )

    # Training config
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs (default: 3)")
    parser.add_argument(
        "--learning-rate", type=float, default=2e-4, help="Learning rate (default: 2e-4)"
    )
    parser.add_argument("--batch-size", type=int, default=4, help="Batch size (default: 4)")
    parser.add_argument(
        "--gradient-accumulation",
        type=int,
        default=4,
        help="Gradient accumulation steps (default: 4)",
    )
    parser.add_argument("--bf16", action="store_true", help="Use bfloat16 (Ampere+ GPUs)")
    parser.add_argument(
        "--load-in-4bit",
        action="store_true",
        default=True,
        help="Load model in 4-bit (default: True)",
    )

    # Export config
    parser.add_argument(
        "--quantization",
        default="q4_k_m",
        help="GGUF quantization method (default: q4_k_m)",
    )
    parser.add_argument(
        "--ollama-name",
        default="autosuggest-finetuned",
        help="Name for Ollama model (default: autosuggest-finetuned)",
    )

    # Modes
    parser.add_argument(
        "--export-only",
        action="store_true",
        help="Skip training, only export from existing adapter",
    )
    parser.add_argument(
        "--adapter-path",
        type=str,
        default=None,
        help="Path to existing adapter (for --export-only)",
    )
    parser.add_argument(
        "--skip-export", action="store_true", help="Skip GGUF export after training"
    )

    args = parser.parse_args()

    # If custom model specified, clear preset
    if args.model:
        args.preset = None

    print("=" * 60)
    print("  AutoSuggest Fine-Tuning (Unsloth)")
    print("=" * 60)

    if args.export_only:
        adapter_path = Path(args.adapter_path or f"{args.output_dir}/adapter")
        if not adapter_path.exists():
            print(f"Error: Adapter not found at {adapter_path}")
            sys.exit(1)
    else:
        adapter_path = train(args)

    if not args.skip_export:
        gguf_path = export_gguf(args, adapter_path)
        if gguf_path.is_file():
            create_ollama_modelfile(args, gguf_path)

    print("\nDone!")


if __name__ == "__main__":
    main()
