# Fine-Tuning Guide

Fine-tune a language model on your AutoSuggest typing data to get personalized completions that match your writing style, vocabulary, and common patterns.

---

## Overview

| Path | Hardware | Speed | Difficulty |
|------|----------|-------|------------|
| **MLX (local Mac)** | Apple Silicon, 8GB+ RAM | ~15 min/epoch | Easy |
| **Google Colab** | Free T4 GPU | ~10 min/epoch | Easy |
| **Unsloth (local CUDA)** | NVIDIA GPU, 6GB+ VRAM | ~5 min/epoch | Medium |
| **Cloud GPU (RunPod, etc.)** | Rented GPU | ~5 min/epoch | Medium |

**Recommended for most users:** MLX on your Mac (simplest) or Google Colab (fastest for free).

---

## Prerequisites

### 1. Collect Training Data

Enable training data collection in AutoSuggest:

1. Open **Settings > Privacy**
2. Toggle **"Allow training data collection"**
3. Use AutoSuggest normally — accepted suggestions are recorded
4. Collect **100+ pairs** minimum (500+ recommended)
5. Export via **Settings > Privacy > Export Training Data**

### 2. Check Your Data

```bash
# Count training pairs
wc -l training-pairs.jsonl

# Preview
head -3 training-pairs.jsonl | python3 -m json.tool
```

Each line is: `{"prompt": "...", "completion": "...", "timestamp": "..."}`

---

## Path A: Fine-Tune on Apple Silicon (MLX)

Best for: M1/M2/M3/M4 Mac users who want to stay local.

### Setup

```bash
cd training/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install MLX dependencies
pip install -r requirements-mlx.txt
```

### Prepare Data

```bash
python prepare_training_data.py /path/to/training-pairs.jsonl \
    --model qwen2.5 \
    --output-dir ./data
```

### Train

```bash
# Default: Qwen 2.5 1.5B (needs 8GB+ RAM)
python finetune_mlx.py --data-dir ./data

# Smaller model for 8GB Macs
python finetune_mlx.py --data-dir ./data --preset qwen2.5-0.5b

# Larger model for 16GB+ Macs
python finetune_mlx.py --data-dir ./data --preset qwen2.5-3b

# More iterations for larger datasets
python finetune_mlx.py --data-dir ./data --iters 1000
```

### Import into Ollama

```bash
cd output-mlx/
# If GGUF was exported:
ollama create autosuggest-finetuned -f Modelfile

# Set in AutoSuggest: Settings > Model > Ollama model name → "autosuggest-finetuned"
```

### Use Directly with MLX (without Ollama)

```bash
# Test interactively
python -m mlx_lm.generate --model output-mlx/fused-model --prompt "Thanks for the"

# Run as a server (OpenAI-compatible)
python -m mlx_lm.server --model output-mlx/fused-model --port 8080
# Then point AutoSuggest's llama.cpp runtime to http://127.0.0.1:8080
```

---

## Path B: Fine-Tune on Google Colab (Free GPU)

Best for: Anyone who wants fast training without local GPU.

### Option 1: Use the Notebook (Easiest)

1. Open [`training/finetune_colab.ipynb`](../training/finetune_colab.ipynb) in Google Colab
2. Runtime > Change runtime type > **T4 GPU** (free) or **A100** (Colab Pro)
3. Run all cells — upload your data when prompted
4. Download the GGUF model + Modelfile at the end
5. Import into Ollama: `ollama create autosuggest-finetuned -f Modelfile`

### Option 2: Upload Scripts to Colab

```python
# In a Colab cell:
!git clone https://github.com/2002bishwajeet/autosuggest.git
%cd autosuggest/training
!pip install -r requirements.txt

# Upload your data
from google.colab import files
uploaded = files.upload()  # upload training-pairs.jsonl

# Prepare and train
!python prepare_training_data.py training-pairs.jsonl --output-dir ./data
!python finetune.py --data-dir ./data --preset qwen2.5-1.5b

# Download result
!zip -r model.zip output/gguf/
files.download("model.zip")
```

---

## Path C: Fine-Tune with Local CUDA GPU (Unsloth)

Best for: Users with an NVIDIA GPU (RTX 3060+ / 6GB+ VRAM).

### Setup

```bash
cd training/

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

### Prepare & Train

```bash
# Prepare data
python prepare_training_data.py /path/to/training-pairs.jsonl --output-dir ./data

# Train (default: Qwen 2.5 1.5B)
python finetune.py --data-dir ./data

# Train with bf16 on Ampere+ GPUs (RTX 3090, 4090, A100)
python finetune.py --data-dir ./data --bf16 --preset qwen2.5-3b

# Custom model
python finetune.py --data-dir ./data --model unsloth/Mistral-7B-Instruct-v0.3
```

### Import into Ollama

```bash
cd output/
# Copy GGUF file and Modelfile are already there
ollama create autosuggest-finetuned -f Modelfile
```

---

## Path D: Cloud GPU Platforms

For users without local GPU who want more control than Colab.

### RunPod

1. Create a GPU pod (A40 recommended, ~$0.40/hr)
2. Select PyTorch template
3. SSH in or use Jupyter:

```bash
git clone https://github.com/2002bishwajeet/autosuggest.git
cd autosuggest/training
pip install -r requirements.txt

# Upload your data via SCP or the Jupyter UI
python prepare_training_data.py training-pairs.jsonl --output-dir ./data
python finetune.py --data-dir ./data
# Download output/gguf/ via SCP
```

### Lambda Labs

Same workflow as RunPod. Lambda offers A10G instances (~$0.50/hr).

```bash
# SSH into your Lambda instance
git clone https://github.com/2002bishwajeet/autosuggest.git
cd autosuggest/training
pip install -r requirements.txt
# ... same as above
```

### Modal (Serverless)

Modal runs functions on cloud GPUs without managing servers.

```python
# modal_train.py
import modal

app = modal.App("autosuggest-finetune")
image = modal.Image.debian_slim(python_version="3.11").pip_install_from_requirements("requirements.txt")

@app.function(gpu="A10G", image=image, timeout=3600)
def train(data_jsonl: bytes):
    import subprocess, tempfile
    from pathlib import Path

    # Write data
    data_dir = Path("/tmp/data")
    data_dir.mkdir(exist_ok=True)
    (data_dir / "raw.jsonl").write_bytes(data_jsonl)

    # Prepare
    subprocess.run(["python", "prepare_training_data.py", str(data_dir / "raw.jsonl"),
                     "--output-dir", str(data_dir)], check=True)

    # Train
    subprocess.run(["python", "finetune.py", "--data-dir", str(data_dir)], check=True)

    # Return GGUF
    gguf_files = list(Path("output/gguf").glob("*.gguf"))
    return gguf_files[0].read_bytes() if gguf_files else None

# Run: modal run modal_train.py
```

### Together AI Fine-Tuning API

Together offers a managed fine-tuning API — no GPU management needed.

1. Export your data in the chat format (prepare_training_data.py already does this)
2. Upload to Together: `together files upload data/train.jsonl`
3. Start fine-tuning via their API or web UI
4. Download the resulting model weights

See [Together docs](https://docs.together.ai/docs/fine-tuning) for details.

---

## Model Selection Guide

| Model | Params | Training RAM/VRAM | Inference RAM | Quality | Speed |
|-------|--------|-------------------|---------------|---------|-------|
| Qwen 2.5 0.5B | 0.5B | 4GB | 1GB | Fair | Fastest |
| **Qwen 2.5 1.5B** | 1.5B | 8GB / 6GB | 2GB | Good | Fast |
| Qwen 2.5 3B | 3B | 16GB / 8GB | 3GB | Better | Medium |
| Qwen 2.5 7B | 7B | 24GB / 16GB | 5GB | Best | Slower |
| Llama 3.2 1B | 1B | 8GB / 6GB | 2GB | Good | Fast |
| Llama 3.2 3B | 3B | 16GB / 8GB | 3GB | Better | Medium |

**Recommendations:**
- **8GB Mac**: Qwen 2.5 0.5B or 1.5B
- **16GB Mac**: Qwen 2.5 1.5B or 3B
- **24GB+ Mac**: Qwen 2.5 3B or 7B
- **Colab free (T4, 15GB)**: Qwen 2.5 1.5B or 3B
- **Colab Pro (A100, 40GB)**: Any model up to 7B

---

## Hyperparameter Guide

### LoRA Settings

| Parameter | Default | When to change |
|-----------|---------|---------------|
| `rank` (r) | 16 | Increase to 32-64 for larger datasets (1000+) |
| `alpha` | 32 | Usually 2x rank. Increase with rank. |
| `dropout` | 0.05 | Increase to 0.1 if overfitting |

### Training Settings

| Parameter | Default | When to change |
|-----------|---------|---------------|
| `epochs` | 3 | 1-2 for large datasets, 5-10 for small (<200) |
| `learning_rate` | 2e-4 (Unsloth) / 1e-4 (MLX) | Lower if loss oscillates |
| `batch_size` | 4 | Decrease if OOM, increase if GPU underutilized |

### Dataset Size Guidelines

| Pairs | Epochs | Expected Result |
|-------|--------|-----------------|
| 10-50 | 10-15 | Minimal personalization |
| 50-200 | 5-8 | Noticeable style adaptation |
| 200-1000 | 3-5 | Good personalization |
| 1000+ | 2-3 | Strong personalization |

---

## Troubleshooting

### Out of Memory (MLX)

```bash
# Use gradient checkpointing
python finetune_mlx.py --data-dir ./data --grad-checkpoint

# Use a smaller model
python finetune_mlx.py --data-dir ./data --preset qwen2.5-0.5b

# Reduce batch size
python finetune_mlx.py --data-dir ./data --batch-size 1
```

### Out of Memory (CUDA)

```bash
# Already using 4-bit by default. Also try:
python finetune.py --data-dir ./data --batch-size 1 --gradient-accumulation 8
```

### Training Loss Not Decreasing

- Check your data quality: `head -5 data/train.jsonl | python3 -m json.tool`
- Try lowering learning rate: `--learning-rate 5e-5`
- Ensure prompts aren't all identical

### Model Outputs Garbage After Training

- Too many epochs (overfitting). Reduce epochs.
- Dataset too small. Collect more pairs.
- Try a lower learning rate.

### GGUF Export Fails

```bash
# Export adapter only, convert manually later
python finetune.py --data-dir ./data --skip-export

# Then use llama.cpp to convert
python llama.cpp/convert_hf_to_gguf.py output/adapter --outfile model.gguf --outtype q4_k_m
```

### Ollama Doesn't Recognize Model

```bash
# Make sure GGUF file is in same directory as Modelfile
ls -la output/gguf/
# Should show: *.gguf and Modelfile

cd output/gguf/
ollama create autosuggest-finetuned -f Modelfile
ollama list  # verify it appears
```

---

## End-to-End Example

Complete walkthrough from data to personalized autocomplete:

```bash
# 1. Export training data from AutoSuggest (Settings > Privacy > Export)
#    This creates a file like: /tmp/autosuggest-training-export-1711411200.jsonl

# 2. Prepare data
cd autosuggest/training
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-mlx.txt  # or requirements.txt for CUDA

python prepare_training_data.py /tmp/autosuggest-training-export-*.jsonl \
    --model qwen2.5 --output-dir ./data

# 3. Train (pick one)
python finetune_mlx.py --data-dir ./data                    # Apple Silicon
python finetune.py --data-dir ./data                         # CUDA GPU

# 4. Import into Ollama
cd output-mlx/gguf/   # or output/gguf/
ollama create autosuggest-finetuned -f Modelfile

# 5. Configure AutoSuggest
# Settings > Model > Ollama model name → "autosuggest-finetuned"

# 6. Done! AutoSuggest now uses your personalized model.
```
