# Training Data Collection

AutoSuggest can optionally collect anonymized training data from accepted suggestions. This data can later be used to fine-tune models for better completion quality.

## Opt-In Only

Training data collection is **disabled by default**. To enable:

1. Open Settings > Privacy
2. Toggle "Allow training data collection"

Or set in config:

```json
{
  "privacy": {
    "trainingDataCollectionEnabled": true
  }
}
```

## What Gets Collected

When you **accept** a suggestion (Tab/Enter), AutoSuggest records:

| Field | Description |
|-------|-------------|
| `prompt` | The text before the cursor (PII-filtered) |
| `completion` | The accepted suggestion text (PII-filtered) |
| `timestamp` | ISO 8601 timestamp |

Dismissed suggestions are **not** recorded.

## Data Format

Training pairs are stored as newline-delimited JSON (JSONL):

```jsonl
{"prompt":"Thanks for the","completion":" quick update on the project","timestamp":"2026-03-26T10:30:00Z"}
{"prompt":"def calculate_","completion":"total(items):","timestamp":"2026-03-26T10:31:15Z"}
```

## PII Filtering

All data passes through the PII filter **twice**:

1. **On recording** — before writing to disk
2. **On export** — defense-in-depth re-scrub

The PII filter removes:
- Email addresses
- Phone numbers
- Credit card numbers
- Social security numbers
- IP addresses
- Common credential patterns (API keys, tokens)

## Storage Location

```
~/Library/Application Support/AutoSuggestApp/TrainingData/training-pairs.jsonl
```

Data is stored locally and is **never** transmitted automatically.

## Export

To export anonymized training data:

1. Open Settings > Privacy
2. Click "Export Training Data"

This creates a timestamped JSONL file in your temp directory with all PII re-filtered.

## Clear Data

To delete all collected training data:

1. Open Settings > Privacy
2. Click "Clear Training Data"

Or delete the file directly:

```bash
rm ~/Library/Application\ Support/AutoSuggestApp/TrainingData/training-pairs.jsonl
```

## Privacy Guarantees

- Collection is opt-in only (disabled by default)
- Data never leaves your machine automatically
- PII is scrubbed on write and again on export
- You can clear all data at any time
- Export format is human-readable for auditing

## Fine-Tuning Your Own Model

See [FINE_TUNING.md](FINE_TUNING.md) for comprehensive instructions on using your collected training data to fine-tune a model locally, on Google Colab, or via cloud training platforms.
