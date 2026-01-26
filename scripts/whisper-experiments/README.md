# Whisper.cpp Experiment Scripts

Individual scripts for running whisper.cpp experiments on Strix Halo (gfx1151).

## Quick Start

Run all experiments with large-v3 model:
```bash
cd /home/tc/softab
./scripts/run-whisper-experiments-v3.sh
```

Run individual experiment:
```bash
./scripts/whisper-experiments/run-sdma-1.sh
```

## Available Experiments

### HIP ROCm Backend

| Script | Configuration | Expected Result |
|--------|--------------|-----------------|
| `run-hip-rocm72.sh` | ROCm 7.2 (default) | ✓ Works, 66x realtime |
| `run-hip-rocm72-mmap.sh` | ROCm 7.2 + mmap | ✓ Works, 62x realtime |
| `run-hip-rocm72-nofa.sh` | ROCm 7.2 (no flash attention) | ✓ Works, 64x realtime |
| `run-sdma-0.sh` | SDMA disabled | ✓ Works, 66x realtime |
| `run-sdma-1.sh` | SDMA enabled | ✓ **BEST: 68x realtime** |
| `run-hip-rocm644.sh` | ROCm 6.4.4 | ✗ Fails (no gfx1151 support) |
| `run-hip-rocm711.sh` | ROCm 7.1.1 | ✗ Fails (partial gfx1151 support) |

### Vulkan Backend

| Script | Configuration | Expected Result |
|--------|--------------|-----------------|
| `run-vulkan-radv.sh` | Vulkan RADV | ✓ Works, 51x realtime |
| `run-vulkan-amdvlk.sh` | Vulkan AMDVLK | ✓ Works, 30x realtime (slower) |

## Usage

Default (uses large-v3 model and test audio):
```bash
./scripts/whisper-experiments/run-sdma-1.sh
```

Custom model and audio:
```bash
./scripts/whisper-experiments/run-sdma-1.sh /models/ggml-base.en.bin /workspace/my-audio.wav
```

## Model Locations

Models are mounted at `/models/` inside containers:
- `/models/ggml-base.en.bin` - Base English model (141 MB)
- `/models/ggml-large-v3.bin` - Large v3 model (3.1 GB)

Host paths:
- `/data/models/whisper/ggml-base.en.bin`
- `/data/models/whisper/ggml-large-v3.bin`

## Test Audio

Test audio is mounted at `/workspace/test_audio.wav`:
- Host path: `/home/tc/softab/samples/test_audio.wav`
- Duration: 300 seconds
- Format: WAV, 16kHz

## Performance Baselines (base.en model, 300s audio)

| Configuration | Time | Speed | Notes |
|--------------|------|-------|-------|
| SDMA=1 (HIP) | 4.4s | 68x | Best |
| SDMA=0 (HIP) | 4.5s | 66x | |
| ROCm 7.2 (HIP) | 4.5s | 66x | Default |
| Vulkan RADV | 5.9s | 51x | |

## Container Flags

HIP experiments require:
- `--device=/dev/kfd` - GPU kernel driver
- `--device=/dev/dri` - Direct rendering
- `--ipc=host` - **Required for ROCm on APU**
- `--security-opt label=disable` - SELinux workaround

Vulkan experiments require:
- `--device=/dev/dri` - Direct rendering
- `--security-opt label=disable` - SELinux workaround

## Troubleshooting

**GPU not detected:**
- Ensure you're using HIP flags for HIP images
- Check `rocminfo` shows your GPU
- Verify `--ipc=host` is set for HIP

**SELinux permission denied:**
- All scripts include `--security-opt label=disable`
- This is required on Fedora

**Model not found:**
- Download models: `~/.local/bin/whisper-download-model large`
- Or manually download from HuggingFace
