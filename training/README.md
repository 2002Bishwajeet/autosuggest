# AutoSuggest Fine-Tuning Toolkit

Fine-tune a language model on your AutoSuggest typing data to get personalized completions.

## Quick Start

### On Apple Silicon Mac (MLX)

```bash
pip install -r requirements-mlx.txt
python prepare_training_data.py /path/to/training-pairs.jsonl --output-dir ./data
python finetune_mlx.py --data-dir ./data
```

### On Google Colab (Free GPU)

Open `finetune_colab.ipynb` in Colab, upload your data, run all cells.

### On CUDA GPU (Unsloth)

```bash
pip install -r requirements.txt
python prepare_training_data.py /path/to/training-pairs.jsonl --output-dir ./data
python finetune.py --data-dir ./data
```

## Files

| File | Description |
|------|-------------|
| `prepare_training_data.py` | Convert AutoSuggest JSONL to training format |
| `finetune_mlx.py` | Train on Apple Silicon (M1/M2/M3/M4) |
| `finetune.py` | Train on CUDA GPU or Colab (Unsloth) |
| `finetune_colab.ipynb` | Ready-to-run Google Colab notebook |
| `requirements.txt` | CUDA/Colab dependencies |
| `requirements-mlx.txt` | Apple Silicon dependencies |

## Full Documentation

See [docs/FINE_TUNING.md](../docs/FINE_TUNING.md) for the comprehensive guide covering:
- Model selection & hardware requirements
- Hyperparameter tuning
- Cloud GPU platforms (RunPod, Lambda, Modal, Together AI)
- Troubleshooting
- End-to-end walkthrough
