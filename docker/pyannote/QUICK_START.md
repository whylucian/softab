# pyannote-audio Quick Start Guide

## 1-Minute Setup

```bash
# 1. Get HuggingFace token
export HF_TOKEN=hf_your_token_here

# 2. Accept model conditions (in browser):
#    https://huggingface.co/pyannote/speaker-diarization-community-1
#    https://huggingface.co/pyannote/segmentation-3.0

# 3. Build recommended image (or all with ./build-all.sh)
podman build \
  -f docker/pyannote/Dockerfile.rocm72-py311-community1 \
  -t softab:pyannote-rocm72-py311-community1-gfx1151 \
  --build-arg GFX_TARGET=gfx1151 \
  .

# 4. Test GPU detection
podman run --rm \
  --device=/dev/kfd --device=/dev/dri --ipc=host \
  -e HF_TOKEN=$HF_TOKEN \
  softab:pyannote-rocm72-py311-community1-gfx1151 \
  python test_diarization.py
```

## Run Diarization on Audio

```bash
# Prepare audio
mkdir -p ~/samples
cp your_audio.wav ~/samples/

# Run diarization
podman run --rm \
  --device=/dev/kfd --device=/dev/dri --ipc=host \
  -e HF_TOKEN=$HF_TOKEN \
  -v ~/samples:/samples:ro \
  softab:pyannote-rocm72-py311-community1-gfx1151 \
  python bench_diarization.py /samples/your_audio.wav
```

## Output Example

```
=== Results ===
Processing time: 12.34s

Speaker segments:
  [0.5s - 12.3s] SPEAKER_00
  [13.1s - 25.7s] SPEAKER_01
  [26.2s - 40.1s] SPEAKER_00
  [41.0s - 55.2s] SPEAKER_01
```

## Critical Flags

- `--ipc=host` - **REQUIRED** (memory access on Strix Halo)
- `--device=/dev/kfd` - AMD KFD device
- `--device=/dev/dri` - DRM/DRI graphics
- `-e HF_TOKEN=...` - HuggingFace token for model download

## Recommended Images

1. **Latest Model**: `softab:pyannote-rocm72-py311-community1-gfx1151`
   - pyannote 4.0+ with community-1 model
   - Best accuracy, especially for noisy audio

2. **Stable Version**: `softab:pyannote-rocm72-py311-v340-gfx1151`
   - pyannote 3.4.0 with speaker-diarization-3.1
   - Community favorite, pinned dependencies

3. **WhisperX**: `softab:whisperx-rocm72-gfx1151`
   - Transcription + diarization in one pipeline
   - Word-level timestamps with speaker labels

## Troubleshooting

**"Memory critical error"** → Add `--ipc=host` flag
**"CUDA available: False"** → Check device flags
**"Model download failed"** → Check HF_TOKEN and accept conditions
**"HSA Error"** (ROCm 6.4.4) → Add `-e HSA_OVERRIDE_GFX_VERSION=11.0.0`

## Full Documentation

- Detailed guide: `docker/pyannote/README.md`
- Experiment summary: `PYANNOTE_EXPERIMENTS.md`
- Knowledge base: `KNOWLEDGE_BASE.md` (section 9)
