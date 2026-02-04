# PyTorch Benchmarks on AMD Strix Halo (gfx1151)

> **Last Updated**: 2026-02-02
> **Hardware**: AMD Ryzen AI Max+ 395, Radeon 8060S (40 CU, gfx1151), 128GB unified memory

## Executive Summary

- **Best config**: TheRock 7.11 with `ROCBLAS_USE_HIPBLASLT=0`
- **Native gfx1151 is 2x faster** for transformers vs gfx1100 fallback
- **CNNs perform the same** across configurations
- **Disable hipBLASLt** for +20% GEMM performance

## GEMM Performance (4096x4096 FP16)

| Configuration | GFX Target | TFLOPS | % of Peak (59.4) |
|--------------|------------|--------|------------------|
| **TheRock 7.11 + hipblaslt=0** | gfx1151 | **32.7** | 55% |
| TheRock 7.11 (default) | gfx1151 | 27.2 | 46% |
| ROCm 6.2 (gfx1100 fallback) | gfx1100 | 25.6 | 43% |

**Key finding**: `ROCBLAS_USE_HIPBLASLT=0` improves performance by ~20%.

## Neural Network Throughput (batch=32, FP16)

| Model | TheRock gfx1151 | ROCm 6.2 gfx1100 | Speedup |
|-------|-----------------|------------------|---------|
| ResNet-18 | 4697 img/s | 4665 img/s | 1.0x |
| ResNet-50 | 1083 img/s | 1085 img/s | 1.0x |
| **ViT-B/16** | **725 img/s** | 317 img/s | **2.3x** |
| **BERT-base (seq=128)** | **1193 seq/s** | 709 seq/s | **1.7x** |
| **BERT-base (seq=512)** | **271 seq/s** | 125 seq/s | **2.2x** |

**Key finding**: CNNs are equal, but **attention-based models are 2x faster on native gfx1151**.

## Image Compatibility Matrix

Tested 75 PyTorch images on 2026-02-02:

| Status | Count | Description |
|--------|-------|-------------|
| **PASS** | 40 | Working (use `python3.12` not `python3`) |
| **INVALID_FUNC** | 17 | Kernels fail at runtime |
| **NO_PY312** | 12 | Image lacks python3.12 |
| **FAIL/OTHER** | 6 | Various failures |

### Working Images (Recommended)

**Native gfx1151 (best for transformers):**
```
softab:pytorch-fedora-rocm          # TheRock 7.11, gfx1151
softab:pytorch-therock-gfx1151      # TheRock 7.11, gfx1151
softab:pytorch-therock-pip-gfx1151  # TheRock 7.11, gfx1151
softab:pytorch-mismatch-fwd-*       # TheRock 7.11, gfx1151
```

**gfx1100 fallback (stable, slower for transformers):**
```
softab:pytorch-rocm644-official     # ROCm 6.2, gfx1100 fallback
softab:pytorch-ablation-*           # ROCm 6.2, gfx1100 fallback
softab:pytorch-official-v3          # ROCm 6.2, gfx1100 fallback
```

### Images That Fail

**INVALID_FUNC (detect gfx1151 but lack kernels):**
```
softab:pytorch-rocm72-official      # Detects gfx1151, crashes on compute
softab:pytorch-nightly-*            # Same issue
softab:pytorch-official-gfx115*     # Same issue
```

## Environment Variables

```bash
# REQUIRED for best performance
export ROCBLAS_USE_HIPBLASLT=0              # +20% GEMM performance
export HSA_ENABLE_SDMA=0                    # Stability fix
export PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"

# NOT recommended (outdated advice)
# export ROCBLAS_USE_HIPBLASLT=1            # Actually HURTS performance
# export HSA_OVERRIDE_GFX_VERSION=11.0.0    # Native gfx1151 now faster
```

## Outdated Claims (Corrected)

| Old Claim | Reality (2026-02) |
|-----------|-------------------|
| "gfx1100 kernels are 2-6x faster" | **FALSE** - Native gfx1151 is 2x faster for transformers |
| "Use HSA_OVERRIDE for better perf" | **FALSE** - Causes instability, native is faster |
| "Enable hipBLASLt for speed" | **FALSE** - Disabling it gives +20% on Strix Halo |

## Running Benchmarks

```bash
# GEMM benchmark
./benchmarks/pytorch-gemm.sh softab:pytorch-fedora-rocm

# Neural network throughput
./benchmarks/pytorch-nn-bench.sh softab:pytorch-fedora-rocm 32

# Quick ablation sweep (requires python3.12 in container)
for img in softab:pytorch-fedora-rocm softab:pytorch-rocm644-official; do
  podman run --rm \
    --device=/dev/kfd --device=/dev/dri \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --security-opt label=disable \
    -e ROCBLAS_USE_HIPBLASLT=0 \
    "$img" python3.12 -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'GFX: {torch.cuda.get_device_properties(0).gcnArchName}')
a = torch.randn(4096, 4096, dtype=torch.float16, device='cuda')
b = torch.randn(4096, 4096, dtype=torch.float16, device='cuda')
import time
for _ in range(10): torch.matmul(a, b)
torch.cuda.synchronize()
t = time.perf_counter()
for _ in range(100): torch.matmul(a, b)
torch.cuda.synchronize()
print(f'TFLOPS: {2*4096**3*100/(time.perf_counter()-t)/1e12:.1f}')
"
done
```

## TheRock vs Official ROCm

| Aspect | TheRock 7.11 Nightlies | Official ROCm 6.2/7.2 |
|--------|------------------------|----------------------|
| gfx1151 target | ✅ Compiled | ❌ Not included |
| Transformer perf | 2x faster | Baseline |
| Stability | Good (nightlies) | Stable |
| Installation | Pip/tarball | System packages |

**Why TheRock is faster**: It's the same code, but TheRock nightlies compile with gfx1151 as a target. Official releases only include "supported" GPUs, so gfx1151 falls back to gfx1100 kernels which miss architecture-specific optimizations.

---

**See also:**
- [ROCm Support](../../docs/rocm-support.md) - Full ROCm documentation
- [Benchmark Scripts](../../benchmarks/) - Test scripts
