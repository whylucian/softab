# Working pyannote-audio Docker Images

**Date**: 2026-01-25
**Status**: ✅ **WORKING - GPU DETECTED**

## Summary

After fixing dependency and PyTorch version issues, we now have working pyannote-audio images with ROCm GPU support.

## Working Image

### `softab:pyannote-rocm62-gfx1151`

**Status**: ✅ **WORKING**

**Specifications:**
- Base: Ubuntu 24.04
- Python: 3.12
- PyTorch: 2.5.1+rocm6.2
- ROCm: 6.2.41133
- pyannote.audio: 3.4.0
- Model: speaker-diarization-3.1

**GPU Detection:**
```
CUDA available: True
CUDA device: AMD Radeon Graphics
```

**Build Command:**
```bash
podman build \
  --security-opt=label=disable \
  -f docker/pyannote/Dockerfile.rocm62-minimal \
  -t softab:pyannote-rocm62-gfx1151 \
  .
```

**Usage:**
```bash
# Test GPU detection (no HF_TOKEN needed)
podman run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --ipc=host \
  softab:pyannote-rocm62-gfx1151 \
  python3 test_diarization.py

# Run speaker diarization (requires HF_TOKEN)
export HF_TOKEN=hf_your_token_here

podman run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --ipc=host \
  -e HF_TOKEN=$HF_TOKEN \
  -v ~/samples:/samples:ro \
  softab:pyannote-rocm62-gfx1151 \
  python3 bench_diarization.py /samples/audio.wav
```

**Size:** ~20 GB

---

## What Was Fixed

### Problem 1: CUDA PyTorch Instead of ROCm
**Original Issue:** Old images installed CUDA PyTorch (2.8.0+cu128) instead of ROCm PyTorch
**Fix:** Explicitly install from ROCm index:
```dockerfile
RUN pip3 install --break-system-packages --no-cache-dir \
    torch torchaudio \
    --index-url https://download.pytorch.org/whl/rocm6.2
```

### Problem 2: Missing Dependencies
**Original Issue:** pyannote.audio missing einops and other dependencies
**Fix:** Install all required dependencies before pyannote:
```dockerfile
RUN pip3 install --break-system-packages --no-cache-dir \
    einops \
    asteroid-filterbanks \
    librosa \
    soundfile \
    numpy \
    scipy \
    huggingface-hub \
    omegaconf \
    "pytorch-metric-learning>=2.0" \
    semver \
    typing-extensions \
    pytorch-lightning \
    pyannote.core \
    pyannote.database \
    pyannote.pipeline \
    pyannote.metrics
```

### Problem 3: torchvision Version Conflicts
**Fix:** Don't install torchvision (not needed for pyannote audio-only tasks)

---

## Complete Stack

| Component | Status | Notes |
|-----------|--------|-------|
| **Whisper (GPU)** | ✅ WORKING | 58x realtime with ROCm HIP |
| **pyannote (GPU)** | ✅ **WORKING** | Speaker diarization with ROCm PyTorch |
| **VAD** | ✅ Built-in | Whisper has VAD, pyannote has voice activity detection |

### Full Pipeline Available

You now have:
1. **Whisper** (whisper.cpp with ROCm HIP) - GPU-accelerated transcription
2. **pyannote** (with ROCm PyTorch) - GPU-accelerated speaker diarization
3. **VAD** - Voice Activity Detection (built into both)

---

## Failed Approaches (For Reference)

### ❌ AMD Official rocm/pytorch:rocm6.1 Image
**Problem:** Missing torchaudio, conda path issues
**Lesson:** Pre-built images have dependency conflicts

### ❌ Installing from Default pip (without --index-url)
**Problem:** Downloads CUDA PyTorch instead of ROCm
**Lesson:** Must explicitly specify ROCm index

### ❌ WhisperX Docker Build
**Problem:** Same CUDA PyTorch issue
**Status:** Can be fixed same way as minimal image

---

## Next Steps

1. ✅ **Test speaker diarization with actual audio** (requires HF_TOKEN)
2. ✅ **Benchmark GPU speedup** (GPU vs CPU)
3. ⚠️ **Build WhisperX properly** (combine Whisper + pyannote in one image)
4. ⚠️ **Test community-1 model** (newer, better than 3.1)
5. ⚠️ **Document in FINDINGS.md**

---

## How to Get HuggingFace Token

1. Create account: https://huggingface.co/join
2. Create token: https://huggingface.co/settings/tokens
3. Accept model conditions:
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0

```bash
export HF_TOKEN=hf_your_token_here
```

---

**Last Updated:** 2026-01-25
**Tested On:** AMD Ryzen AI Max+ 395 / Radeon 8060S (gfx1151)
**Host OS:** Fedora 43, Kernel 6.18.5
