# Whisper.cpp Benchmarks on AMD Strix Halo (gfx1151)

> **Last Updated**: 2026-02-02
> **Hardware**: AMD Ryzen AI Max+ 395, Radeon 8060S (40 CU, gfx1151), 128GB unified memory
> **Test Audio**: 11s JFK "Ask not" speech (test-audio.wav)
> **Model**: ggml-base.en.bin (74M parameters)

## Executive Summary

- **Best config**: ROCm 7.2 HIP with SDMA=1 (~447ms) or hipBLASLt=0 (~459ms)
- **Vulkan RADV/AMDVLK both work** (~533-548ms) - slightly slower than HIP
- **ROCm 6.2/6.4.4 hang** after model load - avoid these versions
- **SDMA=1 slightly faster** than SDMA=0 for whisper (opposite of PyTorch!)

## Benchmark Results (11s audio → transcription time)

| Image | Backend | Total Time | Realtime | Status |
|-------|---------|------------|----------|--------|
| **whisper-ablation-sdma-1** | ROCm 7.2 HIP | **447 ms** | 24.6x | ✅ PASS |
| **whisper-hipblaslt-0** | ROCm 7.2 HIP | **459 ms** | 24.0x | ✅ PASS |
| whisper-ablation-sdma-0 | ROCm 7.2 HIP | 461 ms | 23.9x | ✅ PASS |
| whisper-hip-rocm72-gfx1151 | ROCm 7.2 HIP | 487 ms | 22.6x | ✅ PASS |
| whisper-vulkan-amdvlk | Vulkan AMDVLK | 533 ms | 20.6x | ✅ PASS |
| whisper-vulkan-radv | Vulkan RADV | 547 ms | 20.1x | ✅ PASS |
| softab-toolbox:whisper-vulkan-radv | Vulkan RADV | 548 ms | 20.1x | ✅ PASS |
| whisper-hip-rocm62-gfx1151 | ROCm 6.2 HIP | - | - | ❌ HANG |
| whisper-hip-rocm644-gfx1151 | ROCm 6.4.4 HIP | - | - | ❌ HANG |
| whisper-therock-gfx1151 | TheRock | - | - | ❌ NO CLI |
| whisper-hipblaslt-1 | ROCm HIP | - | - | ❌ NO CLI |

**Realtime** = audio_duration / transcription_time (higher = faster)

## Key Findings

### 1. ROCm 7.2 HIP is Fastest
- ~450-490ms vs ~530-550ms for Vulkan
- ~15% faster than Vulkan backends

### 2. SDMA Behavior Differs from PyTorch
| Setting | PyTorch | Whisper |
|---------|---------|---------|
| SDMA=0 | Recommended | Slightly slower |
| SDMA=1 | May cause artifacts | **Slightly faster** |

For whisper, SDMA=1 appears safe and gives ~3% better performance.

### 3. hipBLASLt=0 Works Well
Unlike PyTorch where hipBLASLt=0 gives +20%, whisper shows minimal difference.

### 4. ROCm 6.x Versions Hang
Both ROCm 6.2 and 6.4.4 hang after loading the model. Use ROCm 7.2+.

### 5. Vulkan: AMDVLK Slightly Faster
- AMDVLK: 533ms
- RADV: 547ms
- Opposite of llama.cpp where RADV is usually better

## Image Compatibility

| Status | Images |
|--------|--------|
| ✅ **Working** | whisper-hip-rocm72-*, whisper-ablation-*, whisper-hipblaslt-0, whisper-vulkan-* |
| ❌ **Hang** | whisper-hip-rocm62-*, whisper-hip-rocm644-* |
| ❌ **Missing CLI** | whisper-therock-*, whisper-hipblaslt-1 |

## Recommended Images

**For production (stability):**
```bash
softab:whisper-vulkan-radv              # Vulkan, most stable
softab-toolbox:whisper-vulkan-radv      # Toolbox variant
```

**For performance (fastest):**
```bash
softab:whisper-ablation-sdma-1          # ROCm 7.2, SDMA=1, fastest
softab:whisper-hipblaslt-0              # ROCm 7.2, hipBLASLt disabled
```

## Running Benchmarks

```bash
# Quick test (11s audio)
./benchmarks/whisper-simple.sh softab:whisper-vulkan-radv /data/models/test-audio.wav

# With timing output
podman run --rm \
  --device=/dev/kfd --device=/dev/dri \
  --ipc=host \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -v /data/models:/models:ro \
  softab:whisper-hip-rocm72-gfx1151 \
  whisper-cli \
    -m /models/ggml-base.en.bin \
    -f /models/test-audio.wav \
    --no-timestamps
```

## Comparison: Whisper vs PyTorch Recommendations

| Setting | PyTorch | Whisper | Notes |
|---------|---------|---------|-------|
| ROCBLAS_USE_HIPBLASLT | **0** (disable) | 0 or 1 | Critical for PyTorch, minimal for Whisper |
| HSA_ENABLE_SDMA | **0** (disable) | 1 (enable) | Opposite recommendations! |
| ROCm version | TheRock 7.11 | ROCm 7.2 | Both work, whisper less picky |
| Vulkan driver | RADV | AMDVLK slightly faster | Different optimal drivers |

## Known Issues

1. **ROCm 6.x hangs** - Model loads but inference never starts
2. **Some images missing whisper-cli** - Build issue, use alternative image
3. **TheRock images use different binary name** - May be `main` instead of `whisper-cli`

---

**See also:**
- [Ablations Added](ABLATIONS_ADDED.md) - Planned ablation tests
- [Benchmark Scripts](../../benchmarks/) - Test scripts
