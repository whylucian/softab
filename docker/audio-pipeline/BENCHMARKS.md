# Audio Pipeline Benchmarks on AMD Strix Halo (gfx1151)

> **Last Updated**: 2026-02-02
> **Hardware**: AMD Ryzen AI Max+ 395, Radeon 8060S (40 CU, gfx1151), 128GB unified memory
> **Container**: softab:audio-pipeline (ROCm 6.2 + Vulkan whisper.cpp)

## Executive Summary

Single-container audio processing pipeline combining:
- **Silero VAD** - Voice Activity Detection (CPU)
- **Whisper.cpp Vulkan** - Speech-to-text transcription (GPU)
- **Pyannote** - Speaker diarization (GPU via ROCm 6.2)

**Why this combination?**
- Whisper: ROCm 7.2 is fastest, but pyannote only works on ROCm 6.2
- Vulkan whisper.cpp works in ROCm 6.2 container (avoids library conflicts)
- Single container simplifies deployment

## Benchmark Results

### Short Audio (11s JFK Speech)

| Stage | Time | Realtime Factor | Backend |
|-------|------|-----------------|---------|
| VAD (Silero) | 1.9s | 5.8x | CPU |
| **Whisper** | **0.6s** | **19x** | Vulkan RADV |
| **Pyannote** | **9.9s** | **1.1x** | ROCm 6.2 |
| **Total** | **12.4s** | **0.9x** | - |

### Long Audio (71 min / 4268s Meeting Recording)

| Stage | Time | Realtime Factor | Backend |
|-------|------|-----------------|---------|
| VAD (Silero) | 23.2s | **184x** | CPU |
| **Whisper** | **64.6s** | **66x** | Vulkan RADV |
| **Pyannote** | **119.4s** | **35.7x** | ROCm 6.2 |
| **Total** | **207.3s** | **20.6x** | - |

- **7 speakers** detected
- **941 diarization segments**
- **1298 speech segments** from VAD

**Key Finding**: Longer audio amortizes model loading overhead significantly. The 71-minute file achieves **20.6x realtime** vs 0.9x for the 11s clip.

**Notes**:
- Pyannote scales better with longer audio (35.7x vs 1.1x realtime)
- Whisper Vulkan achieves 66x realtime on long audio with base.en model
- First run includes model warmup; subsequent runs are faster

## Stage Breakdown

### Stage 1: Voice Activity Detection (Silero)

- **Library**: silero-vad (snakers4/silero-vad)
- **Backend**: CPU (PyTorch)
- **Time**: ~1.9s for 11s audio
- **Output**: Speech segment timestamps

Silero VAD detects speech segments before transcription. This enables:
- Skip silent regions
- Segment audio for parallel processing
- Reduce whisper processing on non-speech

### Stage 2: Transcription (Whisper.cpp Vulkan)

- **Library**: whisper.cpp with GGML_VULKAN
- **Driver**: RADV (AMD_VULKAN_ICD=RADV)
- **Time**: ~580ms for 11s audio (~19x realtime)
- **Model**: ggml-base.en (74M parameters)

Vulkan is used instead of ROCm HIP because:
- ROCm 7.2 HIP conflicts with pyannote's ROCm 6.2 dependencies
- Vulkan works in any container (driver-independent)
- Performance is ~15% slower than HIP but avoids library conflicts

### Stage 3: Speaker Diarization (Pyannote)

- **Library**: pyannote-audio 3.1
- **Model**: pyannote/speaker-diarization-3.1
- **Backend**: ROCm 6.2 (gfx1100 fallback)
- **Time**: ~9.9s for 11s audio (~1.1x realtime)
- **Requires**: HF_TOKEN for gated model access

This is the slowest stage. Diarization involves:
- Speech segmentation
- Speaker embedding extraction
- Clustering algorithm

## Usage

```bash
# Basic usage
podman run --rm \
  --device=/dev/kfd --device=/dev/dri \
  --ipc=host \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -e HF_TOKEN="$HF_TOKEN" \
  -v /data/models:/models:ro \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  softab:audio-pipeline /models/audio.wav -m /models/ggml-base.en.bin

# Skip specific stages
podman run ... softab:audio-pipeline audio.wav --skip-vad
podman run ... softab:audio-pipeline audio.wav --skip-pyannote

# Output to JSON
podman run ... softab:audio-pipeline audio.wav -o /output/result.json
```

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| HSA_ENABLE_SDMA | 0 | Required for ROCm stability on Strix Halo |
| AMD_VULKAN_ICD | RADV | Use Mesa RADV driver for Vulkan |
| HF_TOKEN | (your token) | Required for pyannote model access |

## Comparison with Standalone Containers

| Configuration | Whisper Time | Pyannote Time | Notes |
|---------------|--------------|---------------|-------|
| **Combined Pipeline** | 580ms | 9.9s | Single container |
| Standalone Whisper ROCm 7.2 | 447ms | - | HIP backend, fastest |
| Standalone Whisper Vulkan | 547ms | - | RADV driver |
| Standalone Pyannote ROCm 6.2 | - | 2.5s | Cached model |

**Observation**: Pyannote takes longer in the combined pipeline (~10s) vs standalone (~2.5s). This may be due to:
- First-run model loading overhead
- Shared GPU resources with Silero VAD warmup
- Container-level differences

## Known Issues

1. **First run is slower** - Model warmup for both Silero and Pyannote
2. **HF_TOKEN required** - Pyannote uses gated HuggingFace models
3. **ROCm warnings** - hipBLASLt disabled (expected on gfx1151 fallback)
4. **TF32 disabled** - Pyannote disables for reproducibility

## Building the Container

```bash
cd docker/audio-pipeline
podman build \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -t softab:audio-pipeline \
  -f Dockerfile.rocm62-vulkan .
```

## Future Improvements

- [ ] Add whisper-large-v3 benchmarks (~6x realtime expected)
- [ ] Investigate pyannote caching for faster subsequent runs
- [ ] Test with longer audio files (60+ minutes)
- [ ] Add word-level timestamp merging for diarization

---

**See also:**
- [Whisper Benchmarks](../whisper-cpp/BENCHMARKS.md) - Standalone whisper comparison
- [Pyannote Benchmarks](../pyannote/BENCHMARKS.md) - Standalone pyannote comparison
