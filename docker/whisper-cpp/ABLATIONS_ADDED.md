# Whisper.cpp Ablations Added - 2026-01-24

## Summary

Added **9 new Dockerfiles** to fill identified gaps in whisper.cpp ablation coverage.

## High Priority Ablations (3 files)

### 1. SDMA Controlled Pair
**Purpose**: Test stability vs performance trade-off (same as PyTorch/llama.cpp ablations)

- `Dockerfile.ablation-sdma-0` - SDMA disabled (recommended default)
- `Dockerfile.ablation-sdma-1` - SDMA enabled (test for artifacts)

**Expected**: SDMA=0 more stable, SDMA=1 may cause issues like PyTorch

### 2. Flash Attention Ablation
**Purpose**: Quantify impact of flash attention on whisper workload

- `Dockerfile.hip-rocm72-nofa` - Flash attention disabled at compile time

**Compare with**: Existing `Dockerfile.hip-rocm72` (flash attention enabled by default)

**Expected**: Significant performance difference (README states "flash attention enabled by default" but impact unquantified)

## Medium Priority Ablations (6 files)

### 3. ROCm 7.1.1 Version Gap
**Purpose**: Test if ROCm 7.1.1 fails like llama.cpp (segfaults during model loading)

- `Dockerfile.hip-rocm711` - ROCm 7.1.1 HIP build

**Expected**: FAIL (segfaults like llama.cpp)

### 4. Memory Mapping Ablation
**Purpose**: Test if --no-mmap is critical for whisper like it is for llama.cpp (kyuz0 requirement)

- `Dockerfile.hip-rocm72-mmap` - mmap enabled (default behavior)

**Compare with**: Existing `Dockerfile.hip-rocm72` (uses --no-mmap in benchmark)

**Expected**: Performance degradation with mmap enabled

### 5. Vulkan Driver-Specific Builds
**Purpose**: Test RADV vs AMDVLK performance for whisper (llama.cpp RADV = 5369 t/s, AMDVLK falls back to CPU)

- `Dockerfile.vulkan-radv` - RADV driver (Mesa)
- `Dockerfile.vulkan-amdvlk` - AMDVLK driver (AMD proprietary)

**Compare with**: Existing `Dockerfile.vulkan` (generic, defaults to RADV)

**Expected**: RADV works well, AMDVLK may not detect GPU on gfx1151

## Build Commands

### High Priority - SDMA Ablation Pair
```bash
podman build -t softab:whisper-ablation-sdma-0 \
  -f docker/whisper-cpp/Dockerfile.ablation-sdma-0 .

podman build -t softab:whisper-ablation-sdma-1 \
  -f docker/whisper-cpp/Dockerfile.ablation-sdma-1 .
```

### High Priority - Flash Attention
```bash
podman build -t softab:whisper-hip-rocm72-nofa-gfx1151 \
  -f docker/whisper-cpp/Dockerfile.hip-rocm72-nofa .
```

### Medium Priority - ROCm Version
```bash
podman build -t softab:whisper-hip-rocm711-gfx1151 \
  -f docker/whisper-cpp/Dockerfile.hip-rocm711 .
```

### Medium Priority - Memory Mapping
```bash
podman build -t softab:whisper-hip-rocm72-mmap-gfx1151 \
  -f docker/whisper-cpp/Dockerfile.hip-rocm72-mmap .
```

### Medium Priority - Vulkan Drivers
```bash
podman build -t softab:whisper-vulkan-radv \
  -f docker/whisper-cpp/Dockerfile.vulkan-radv .

podman build -t softab:whisper-vulkan-amdvlk \
  -f docker/whisper-cpp/Dockerfile.vulkan-amdvlk .
```

## Test Commands

All tests require audio file and model:

```bash
# Download test audio (if not already done)
./samples/download-test-audio.sh

# Download whisper model
mkdir -p ~/models
cd ~/models
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

### Run SDMA Ablation Comparison
```bash
# SDMA disabled
podman run --rm --ipc=host --device=/dev/kfd --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-ablation-sdma-0 run-bench /samples/test_audio.wav /models/ggml-base.en.bin

# SDMA enabled
podman run --rm --ipc=host --device=/dev/kfd --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-ablation-sdma-1 run-bench /samples/test_audio.wav /models/ggml-base.en.bin
```

### Run Flash Attention Comparison
```bash
# With flash attention (baseline)
podman run --rm --ipc=host --device=/dev/kfd --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-hip-rocm72-gfx1151 run-bench /samples/test_audio.wav /models/ggml-base.en.bin

# Without flash attention
podman run --rm --ipc=host --device=/dev/kfd --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-hip-rocm72-nofa-gfx1151 run-bench /samples/test_audio.wav /models/ggml-base.en.bin
```

### Run Vulkan Driver Comparison
```bash
# RADV driver
podman run --rm --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-vulkan-radv run-bench /samples/test_audio.wav /models/ggml-base.en.bin

# AMDVLK driver
podman run --rm --device=/dev/dri \
  -v ~/models:/models -v ./samples:/samples \
  softab:whisper-vulkan-amdvlk run-bench /samples/test_audio.wav /models/ggml-base.en.bin
```

## Files Before vs After

### Before
```
docker/whisper-cpp/
├── Dockerfile.hip              # ROCm 6.4.3 (fails)
├── Dockerfile.hip-rocm644      # ROCm 6.4.4 (gap fill)
├── Dockerfile.hip-rocm70       # ROCm 7.0.1 (gap fill)
├── Dockerfile.hip-rocm72       # ROCm 7.2 (works)
├── Dockerfile.therock          # TheRock nightlies
└── Dockerfile.vulkan           # Vulkan generic
```

### After
```
docker/whisper-cpp/
├── Dockerfile.hip              # ROCm 6.4.3 (fails)
├── Dockerfile.hip-rocm644      # ROCm 6.4.4 (gap fill)
├── Dockerfile.hip-rocm70       # ROCm 7.0.1 (gap fill)
├── Dockerfile.hip-rocm711      # [NEW] ROCm 7.1.1 (version gap)
├── Dockerfile.hip-rocm72       # ROCm 7.2 (works)
├── Dockerfile.hip-rocm72-mmap  # [NEW] ROCm 7.2 + mmap enabled
├── Dockerfile.hip-rocm72-nofa  # [NEW] ROCm 7.2 - flash attention disabled
├── Dockerfile.therock          # TheRock nightlies
├── Dockerfile.vulkan           # Vulkan generic
├── Dockerfile.vulkan-radv      # [NEW] Vulkan RADV driver
├── Dockerfile.vulkan-amdvlk    # [NEW] Vulkan AMDVLK driver
├── Dockerfile.ablation-sdma-0  # [NEW] SDMA disabled (controlled)
└── Dockerfile.ablation-sdma-1  # [NEW] SDMA enabled (controlled)
```

**Total whisper.cpp images**: 6 → 13 (+7 new + 2 SDMA ablations = +9 total)

## Integration with Existing Ablations

These whisper.cpp ablations mirror existing llama.cpp and PyTorch ablation patterns:

| Ablation Type | PyTorch | llama.cpp | whisper.cpp |
|--------------|---------|-----------|-------------|
| SDMA pair | ✅ | ✅ | ✅ **NEW** |
| Flash Attention | N/A | ✅ | ✅ **NEW** |
| Memory Mapping | N/A | ✅ | ✅ **NEW** |
| Vulkan RADV | N/A | ✅ | ✅ **NEW** |
| Vulkan AMDVLK | N/A | ✅ | ✅ **NEW** |
| ROCm 7.1.1 | N/A | ✅ | ✅ **NEW** |

## Expected Results Summary

| Ablation | Expected Status | Expected Performance |
|----------|----------------|---------------------|
| SDMA=0 vs SDMA=1 | Both work | SDMA=0 more stable |
| Flash Attention ON vs OFF | Both work | ON significantly faster |
| mmap enabled vs disabled | Both work | disabled (--no-mmap) faster |
| RADV vs AMDVLK | RADV works, AMDVLK may fail | RADV faster |
| ROCm 7.1.1 | **FAIL** | Segfaults (like llama.cpp) |

## Next Steps

1. Build all 9 images (~45 min total)
2. Run controlled ablation tests with same audio/model
3. Document results in ABLATION_SUMMARY.md
4. Update CHANGELOG_ABLATIONS.md with whisper additions
5. Compare whisper results to llama.cpp findings

## Notes

- All HIP builds require `--ipc=host` flag for ROCm 7.x on Strix Halo
- Vulkan builds only need `--device=/dev/dri` (no --ipc=host)
- Use ggml-base.en model for consistent testing (74M parameters)
- Use 300s test audio from samples/test_audio.wav
- Baseline performance: 5.14s for 300s audio = 58x realtime (from README.md)
