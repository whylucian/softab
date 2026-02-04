# Pyannote Benchmarks on AMD Strix Halo (gfx1151)

> **Last Updated**: 2026-02-02
> **Hardware**: AMD Ryzen AI Max+ 395, Radeon 8060S (40 CU, gfx1151), 128GB unified memory
> **Test Audio**: 11s JFK speech (test-audio.wav)
> **Model**: pyannote/speaker-diarization-3.1

## Executive Summary

- **Best config**: ROCm 6.2 with gfx1100 fallback (~2.5-2.7s for 11s audio)
- **ROCm 7.2 / TheRock images have dependency issues** (lightning import errors)
- **Requires HF_TOKEN** for model download (gated model)
- **4x realtime** speaker diarization on GPU

## Benchmark Results (11s audio → diarization time)

| Image | PyTorch | GFX | Time | Realtime | Status |
|-------|---------|-----|------|----------|--------|
| **pyannote-rocm62-gfx1151** | 2.5.1+rocm6.2 | gfx1100 | **2.54s** | 4.3x | ✅ PASS |
| **pyannote-rocm62-working-gfx1151** | 2.5.1+rocm6.2 | gfx1100 | **2.59s** | 4.2x | ✅ PASS |
| pyannote-rocm72-amd-gfx1151 | - | - | - | - | ❌ Import error |
| pyannote-rocm644-gfx1151 | - | - | - | - | ❌ Import error |
| pyannote-therock-gfx1151 | - | - | - | - | ❌ Import error |

**Realtime** = audio_duration / processing_time (higher = faster)

## Key Findings

### 1. Only ROCm 6.2 Images Work
- ROCm 7.2, 6.4.4, and TheRock images fail with `lightning.pytorch` import errors
- Likely dependency version mismatch with pyannote-audio

### 2. Uses gfx1100 Fallback
- Working images use gfx1100 (not native gfx1151)
- hipBLASLt automatically disabled ("unsupported architecture")
- Still achieves good performance via fallback

### 3. Performance Characteristics
- ~2.5s for 11s audio = **4.3x realtime**
- Consistent across runs (low variance)
- GPU memory usage: ~2-3GB for speaker-diarization-3.1

## Image Compatibility

| Status | Images |
|--------|--------|
| ✅ **Working** | pyannote-rocm62-gfx1151, pyannote-rocm62-working-gfx1151 |
| ❌ **Import Error** | pyannote-rocm72-*, pyannote-rocm644-*, pyannote-therock-* |
| ❓ **Untested** | pyannote-rocm62-minimal-gfx1151 |

### Error Details (ROCm 7.x images)
```
ImportError: cannot import name 'is_oom_error' from 'lightning.pytorch.utilities.memory'
```
This is a pyannote-audio / pytorch-lightning version mismatch.

## Prerequisites

### HuggingFace Token
Pyannote models are gated - requires accepted license and token:
1. Accept license at https://huggingface.co/pyannote/speaker-diarization-3.1
2. Get token from https://huggingface.co/settings/tokens
3. Pass via `HF_TOKEN` environment variable

### Monkeypatch for Token Handling
Older pyannote uses `use_auth_token`, newer huggingface_hub uses `token`:
```python
import huggingface_hub
_orig = huggingface_hub.hf_hub_download
def _patched(*args, **kwargs):
    if 'use_auth_token' in kwargs:
        kwargs['token'] = kwargs.pop('use_auth_token')
    return _orig(*args, **kwargs)
huggingface_hub.hf_hub_download = _patched
```

## Running Benchmarks

```bash
# Using benchmark script
export HF_TOKEN="your_token_here"
./benchmarks/pyannote-simple.sh softab:pyannote-rocm62-gfx1151 /data/models/test-audio.wav

# Direct run
podman run --rm \
  --device=/dev/kfd --device=/dev/dri \
  --ipc=host \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -e HF_TOKEN="$HF_TOKEN" \
  -v /data/models:/audio:ro \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  softab:pyannote-rocm62-gfx1151 \
  python3 -c "
import torch
from pyannote.audio import Pipeline
pipeline = Pipeline.from_pretrained('pyannote/speaker-diarization-3.1')
pipeline.to(torch.device('cuda'))
diarization = pipeline('/audio/test-audio.wav')
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f'[{turn.start:.1f}s - {turn.end:.1f}s] {speaker}')
"
```

## Comparison with Other Workloads

| Workload | Best Backend | Realtime Factor | Notes |
|----------|--------------|-----------------|-------|
| Whisper (11s) | ROCm 7.2 HIP | 24.6x | Transcription |
| **Pyannote (11s)** | ROCm 6.2 | **4.3x** | Diarization |
| PyTorch ViT | TheRock 7.11 | - | 725 img/s |

Pyannote is slower than Whisper because diarization involves:
- Multiple neural network passes (segmentation, embedding, clustering)
- Speaker embedding extraction for each segment
- Clustering algorithm on embeddings

## Known Issues

1. **ROCm 7.x dependency mismatch** - pyannote-audio incompatible with newer lightning
2. **Requires monkeypatch** - Token parameter name changed in huggingface_hub
3. **TF32 disabled warning** - pyannote disables TF32 for reproducibility
4. **hipBLASLt warning** - Automatically falls back to hipblas

## Recommended Setup

For speaker diarization on Strix Halo:
```bash
# Use the working ROCm 6.2 image
softab:pyannote-rocm62-gfx1151

# Or the explicitly named "working" variant
softab:pyannote-rocm62-working-gfx1151
```

---

**See also:**
- [Whisper Benchmarks](../whisper-cpp/BENCHMARKS.md) - Speech-to-text comparison
- [PyTorch Benchmarks](../pytorch/BENCHMARKS.md) - General PyTorch performance
