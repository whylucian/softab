# pyannote-audio Experiments for AMD Strix Halo (gfx1151)

Speaker diarization ("who spoke when") experiments using pyannote-audio on ROCm.

## Overview

pyannote-audio is a PyTorch-based speaker diarization toolkit that identifies and labels different speakers in audio recordings. These Docker images test various configurations to find optimal performance on Strix Halo's Radeon 8060S GPU.

**Key Points:**
- **Voice Activity Detection (VOD)** can run on CPU - that's fine
- **Speaker embeddings and diarization** should leverage GPU for speed
- Requires HuggingFace token (models are gated resources)

## Available Images

### ROCm 7.2 (Native gfx1151 Support)

| Image | Python | pyannote | Model | Notes |
|-------|--------|----------|-------|-------|
| `Dockerfile.rocm72-py310` | 3.10 | 4.0+ | community-1 | Baseline |
| `Dockerfile.rocm72-py311-community1` | 3.11 | 4.0+ | community-1 | **Recommended** - latest model |
| `Dockerfile.rocm72-py311-v340` | 3.11 | 3.4.0 | speaker-diarization-3.1 | Community favorite - stable |

### ROCm 6.4.4 (Stable Stepping Stone)

| Image | Python | pyannote | Model | Notes |
|-------|--------|----------|-------|-------|
| `Dockerfile.rocm644-py310` | 3.10 | 4.0+ | community-1 | May need HSA_OVERRIDE |

### scottt/TheRock Wheels (Native gfx1151 PyTorch)

| Image | Python | pyannote | Model | Notes |
|-------|--------|----------|-------|-------|
| `Dockerfile.therock-py311` | 3.11 | 4.0+ | community-1 | Self-contained PyTorch 2.7 |

## Model Comparison

### community-1 (pyannote.audio 4.0+)
- Released September 2025 - latest open-source model
- **Significantly better** than 3.1 across all metrics
- Better speaker counting and assignment
- Reduced speaker confusion
- New "exclusive speaker diarization" output
- Better for noisy, real-world audio
- Model: `pyannote/speaker-diarization-community-1`

### speaker-diarization-3.1 (pyannote.audio 3.x)
- Released 2023 - mature and stable
- **Version 3.4.0** (Sept 2025) - last 3.x release with pinned dependencies
- Community favorite for stability
- Good for clean audio conditions
- Model: `pyannote/speaker-diarization-3.1`

## Prerequisites

### 1. Get HuggingFace Token

```bash
# Create token at: https://huggingface.co/settings/tokens
# Accept user conditions for models:

# For community-1:
https://huggingface.co/pyannote/speaker-diarization-community-1

# For 3.1:
https://huggingface.co/pyannote/speaker-diarization-3.1

# Also accept segmentation model:
https://huggingface.co/pyannote/segmentation-3.0
```

### 2. Prepare Test Audio

```bash
# Copy audio files to test with
mkdir -p ~/samples
cp your_audio.wav ~/samples/test.wav

# Or use whisper test audio
cp samples/test_audio.wav ~/samples/
```

## Build Instructions

```bash
# Build ROCm 7.2 with community-1 (recommended)
podman build \
  -f docker/pyannote/Dockerfile.rocm72-py311-community1 \
  -t softab:pyannote-rocm72-py311-community1-gfx1151 \
  --build-arg GFX_TARGET=gfx1151 \
  .

# Build version 3.4.0 (community favorite)
podman build \
  -f docker/pyannote/Dockerfile.rocm72-py311-v340 \
  -t softab:pyannote-rocm72-py311-v340-gfx1151 \
  --build-arg GFX_TARGET=gfx1151 \
  .

# Build with TheRock wheels
podman build \
  -f docker/pyannote/Dockerfile.therock-py311 \
  -t softab:pyannote-therock-py311-gfx1151 \
  --build-arg GFX_TARGET=gfx1151 \
  .
```

## Run Instructions

### Test GPU Detection

```bash
# IMPORTANT: Use --ipc=host flag (required for ROCm on Strix Halo)
podman run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --ipc=host \
  -e HF_TOKEN=hf_your_token_here \
  softab:pyannote-rocm72-py311-community1-gfx1151 \
  python test_diarization.py
```

Expected output:
```
=== pyannote-audio 4.0 community-1 ROCm Test ===
Python: 3.11.x
PyTorch: 2.x.x+rocm6.2
pyannote.audio: 4.0.x
CUDA available: True
CUDA device: Radeon 8060S
CUDA device count: 1
Loading speaker-diarization-community-1 pipeline...
Pipeline loaded successfully!
Moving pipeline to GPU...
Pipeline on GPU!
Test completed successfully!
```

### Run Diarization Benchmark

```bash
podman run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --ipc=host \
  -e HF_TOKEN=hf_your_token_here \
  -v ~/samples:/samples:ro \
  softab:pyannote-rocm72-py311-community1-gfx1151 \
  python bench_diarization.py /samples/test.wav
```

Expected output:
```
=== pyannote-audio community-1 Benchmark ===
Audio file: /samples/test.wav
Device: CUDA
Loading community-1 pipeline...
Running speaker diarization...

=== Results ===
Processing time: X.XXs

Speaker segments:
  [0.5s - 12.3s] SPEAKER_00
  [13.1s - 25.7s] SPEAKER_01
  [26.2s - 40.1s] SPEAKER_00
```

## Comparison Script

Create a comparison script to test multiple images:

```bash
#!/bin/bash
# compare_pyannote.sh

AUDIO="${1:-~/samples/test.wav}"
HF_TOKEN="${HF_TOKEN:-}"

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: Set HF_TOKEN environment variable"
    exit 1
fi

echo "=== pyannote-audio ROCm Comparison ==="
echo "Audio: $AUDIO"
echo ""

for image in \
    softab:pyannote-rocm72-py311-community1-gfx1151 \
    softab:pyannote-rocm72-py311-v340-gfx1151 \
    softab:pyannote-therock-py311-gfx1151
do
    echo "Testing: $image"
    podman run --rm \
        --device=/dev/kfd --device=/dev/dri --ipc=host \
        -e HF_TOKEN="$HF_TOKEN" \
        -v "$(dirname $AUDIO)":/samples:ro \
        "$image" \
        python bench_diarization.py "/samples/$(basename $AUDIO)" 2>&1 | \
        grep -E "(Processing time|SPEAKER_)"
    echo ""
done
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `HF_TOKEN` | **Yes** | HuggingFace access token |
| `HSA_ENABLE_SDMA` | Auto-set | Disabled (0) for stability |
| `HIP_VISIBLE_DEVICES` | Auto-set | GPU device ID (0) |
| `ROCBLAS_USE_HIPBLASLT` | Auto-set | Use hipBLASLt for performance |
| `HSA_OVERRIDE_GFX_VERSION` | Maybe | Set to `11.0.0` for ROCm 6.4.4 if needed |

## Performance Expectations

Based on AMD's ROCm blog and community testing:

| Component | Device | Expected Speed |
|-----------|--------|----------------|
| Voice Activity Detection (VOD) | CPU or GPU | Fast either way |
| Speaker Embeddings | **GPU** | ~10-50x faster than CPU |
| Clustering/Assignment | CPU | Lightweight |

**Overall:** GPU acceleration provides significant speedup (10-50x) for the embedding extraction phase.

## Troubleshooting

### "HSA Error: Device kernel image is invalid"

ROCm 6.4.4 may need:
```bash
podman run -e HSA_OVERRIDE_GFX_VERSION=11.0.0 ...
```

### "Memory critical error by agent node-0"

Missing `--ipc=host` flag:
```bash
podman run --ipc=host ...
```

### "CUDA available: False"

Check device permissions:
```bash
ls -l /dev/kfd /dev/dri
podman run --device=/dev/kfd --device=/dev/dri ...
```

### Model Download Fails

Check HuggingFace token and model access:
```bash
# Verify token works
curl -H "Authorization: Bearer $HF_TOKEN" \
  https://huggingface.co/api/whoami

# Accept model conditions (must do in browser):
# https://huggingface.co/pyannote/speaker-diarization-community-1
# https://huggingface.co/pyannote/segmentation-3.0
```

## References

- [AMD ROCm Blog: Speech Models](https://rocm.blogs.amd.com/artificial-intelligence/speech_models/README.html) - Official AMD guide
- [pyannote-audio GitHub](https://github.com/pyannote/pyannote-audio) - Official repository
- [community-1 Announcement](https://www.pyannote.ai/blog/community-1) - Model improvements
- [speaker-diarization-community-1 (HF)](https://huggingface.co/pyannote/speaker-diarization-community-1) - Latest model
- [speaker-diarization-3.1 (HF)](https://huggingface.co/pyannote/speaker-diarization-3.1) - Stable 3.x model
- [scottt/rocm-TheRock](https://github.com/scottt/rocm-TheRock) - gfx1151 PyTorch wheels

## Integration with Whisper

For combined transcription + diarization, see WhisperX experiments (coming soon).

## Expected Results

After testing, we expect to document:
1. Which ROCm version works best (7.2 vs 6.4.4 vs TheRock)
2. Performance difference between community-1 and 3.1 models
3. GPU speedup vs CPU baseline
4. Python version impact (3.10 vs 3.11)
5. Memory usage for different audio lengths

Results will be added to `KNOWLEDGE_BASE.md` once testing is complete.
