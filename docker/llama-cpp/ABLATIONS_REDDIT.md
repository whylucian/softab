# Reddit-Inspired Ablation Dockerfiles

**Created:** 2026-01-27
**Source:** [r/LocalLLaMA Strix Halo Benchmarks](https://www.reddit.com/r/LocalLLaMA/comments/...) by u/randomfoo2

## Summary

These Dockerfiles test configurations mentioned in community benchmarks that weren't previously covered.

## New Dockerfiles

### 1. TheRock Tarball Extraction
**Dockerfile:** `Dockerfile.therock-tarball`
**Purpose:** Test extracted tarball approach vs pip install (per lhl's strix-halo-testing)

The Reddit approach extracts TheRock nightlies as a tarball with a full environment setup script, different from our existing `Dockerfile.therock` which uses pip install.

```bash
podman build -t softab:llama-therock-tarball -f Dockerfile.therock-tarball .
podman run --device /dev/kfd --device /dev/dri -v ~/models:/models \
  -e MODEL=/models/test.gguf softab:llama-therock-tarball
```

---

### 2. Vulkan Batch Size Ablations
**Dockerfiles:** `Dockerfile.vulkan-radv-ub1024`, `Dockerfile.vulkan-amdvlk-ub512`
**Purpose:** Test optimal batch sizes per driver

Reddit benchmarks show:
- **RADV optimal:** `-ub 1024`
- **AMDVLK optimal:** `-ub 512`

```bash
# Build both
podman build -t softab:llama-vulkan-radv-ub1024 -f Dockerfile.vulkan-radv-ub1024 .
podman build -t softab:llama-vulkan-amdvlk-ub512 -f Dockerfile.vulkan-amdvlk-ub512 .

# Compare against defaults
podman build -t softab:llama-vulkan-radv -f Dockerfile.vulkan-radv .
podman build -t softab:llama-vulkan-amdvlk -f Dockerfile.vulkan-amdvlk .
```

---

### 3. hipBLASLt Ablation
**Dockerfiles:** `Dockerfile.ablation-hipblaslt-0`, `Dockerfile.ablation-hipblaslt-1`
**Purpose:** Measure impact of `ROCBLAS_USE_HIPBLASLT=1`

Reddit claims "almost always faster than default rocBLAS". This ablation quantifies the difference.

```bash
# Build both
podman build -t softab:llama-hipblaslt-0 -f Dockerfile.ablation-hipblaslt-0 .
podman build -t softab:llama-hipblaslt-1 -f Dockerfile.ablation-hipblaslt-1 .

# Run comparison
podman run --device /dev/kfd --device /dev/dri -v ~/models:/models \
  -e MODEL=/models/test.gguf softab:llama-hipblaslt-0
podman run --device /dev/kfd --device /dev/dri -v ~/models:/models \
  -e MODEL=/models/test.gguf softab:llama-hipblaslt-1
```

---

### 4. gfx1100 Override (OUTDATED - NOT RECOMMENDED)
**Dockerfile:** `Dockerfile.hip-gfx1100-override`
**Purpose:** ~~Test "2x faster" claim~~ **OUTDATED** - native gfx1151 is now faster

**WARNING:** May cause system hangs requiring reboot!

> ⚠️ **UPDATE (2026-02-02):** The claim that "gfx1100 kernels are 2x faster" is **no longer true**. SoftAb benchmarks show TheRock 7.11 with native gfx1151 is actually **2x faster for transformer models** (ViT, BERT). CNNs perform the same. The old claim (tracked in [ROCm/ROCm#4748](https://github.com/ROCm/ROCm/issues/4748)) was true for early unoptimized gfx1151 kernels but has been fixed.

```bash
# Build
podman build -t softab:llama-gfx1100-override -f Dockerfile.hip-gfx1100-override .

# Run (SAVE WORK FIRST)
podman run --device /dev/kfd --device /dev/dri -v ~/models:/models \
  -e MODEL=/models/test.gguf softab:llama-gfx1100-override
```

---

### 5. MoE-Optimized Configuration
**Dockerfile:** `Dockerfile.moe-optimized`
**Purpose:** Optimal settings for Mixture-of-Experts models

Reddit emphasizes Strix Halo excels at MoE due to large VRAM. Optimized settings:
- Flash Attention enabled (`-fa 1`)
- Batch size 256 (`-b 256`)
- Vulkan RADV (stability for long runs)

Recommended models:
- Qwen3-30B-A3B (3B active): ~72 t/s
- dots1 142B (14B active): ~21 t/s
- Llama 4 Scout 109B (17B active): ~17-19 t/s

```bash
podman build -t softab:llama-moe -f Dockerfile.moe-optimized .
podman run --device /dev/dri -v ~/models:/models \
  -e MODEL=/models/qwen3-30b-a3b.gguf softab:llama-moe
```

---

## Sweep Script

Run all ablations automatically:

```bash
cd docker/llama-cpp
./run-ablation-sweep.sh /path/to/model.gguf ./results/
```

Output: CSV file with pp512/tg128 results for each configuration.

---

## Expected Findings

| Ablation | Expected Impact | Source |
|----------|-----------------|--------|
| hipBLASLt=1 vs 0 | 10-30% faster | Reddit |
| RADV -ub 1024 | Optimal for tg | Reddit |
| AMDVLK -ub 512 | Optimal for pp | Reddit |
| gfx1100 override | Up to 2x (risky) | Reddit |
| MoE + batch 256 | Best for MoE models | Reddit |

---

## Related Issues

- gfx1100 vs gfx1151 regression: https://github.com/ROCm/ROCm/issues/4748
- HIP_VERSION fix for ROCm 7.0: https://www.reddit.com/r/LocalLLaMA/comments/1m6b151/comment/n4jlc3z
