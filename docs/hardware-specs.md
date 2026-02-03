# AMD Strix Halo Hardware Specifications

> **Hardware Target**: AMD Ryzen AI Max+ 395 (Strix Halo) with Radeon 8060S iGPU

## GPU Compute Specifications

| Metric | Value |
|--------|-------|
| Architecture | RDNA 3.5 (gfx1151) |
| Compute Units | 40 |
| Max Clock | 2.9 GHz |
| Peak FP16/BF16 | 59.4 TFLOPS |
| Peak INT8 | 59.4 TOPS |
| Peak INT4 | 118.8 TOPS |
| Memory | 128GB LPDDR5X-8000 (unified) |
| Memory Bandwidth | 256 GB/s theoretical, **~215 GB/s measured** (84% efficiency) |

**Peak FP16 Calculation**: `512 ops/clock/CU × 40 CU × 2.9e9 clock / 1e12 = 59.392 TFLOPS`

## Comparison with Competition

| Spec | Strix Halo 395 | Mac Studio M4 Max | DGX Spark | RTX PRO 6000 |
|------|----------------|-------------------|-----------|--------------|
| Price | $2,000 | $3,499 | $4,000 | $8,200 |
| Power (Max W) | 120 | 300+ | 240 | 600 |
| Memory | 128GB | 128GB | 128GB | 96GB GDDR7 |
| Memory BW | 256 GB/s | 546 GB/s | 273 GB/s | 1792 GB/s |
| FP16 TFLOPS | 59.4 | 34.1 | 62.5 | 251.9 |

**Key Advantage**: Strix Halo trades bandwidth for capacity—ideal for:
- Huge MoE models (70B+, 235B Q3_K)
- Long-context scenarios (32K+ tokens)
- Data that fits entirely in unified memory

## Memory Architecture

### Understanding GTT vs GART

- **GART**: Fixed reserved aperture set in BIOS (set to minimum: 512MB)
- **GTT**: Dynamically allocatable via TTM subsystem (configure in Linux)

### Linux Memory Configuration

Create `/etc/modprobe.d/amdgpu-ai.conf`:

```bash
# GTT allocation via TTM (pages_limit × 4KB = total bytes)
# 31457280 pages × 4KB = 120 GiB
options ttm pages_limit=31457280

# Optional: Pre-allocate to reduce fragmentation
# Set equal to pages_limit for AI-dedicated systems
options ttm page_pool_size=31457280

# Legacy parameter (still set for compatibility)
options amdgpu gttsize=122800
```

### Kernel Parameters

Add to `GRUB_CMDLINE_LINUX_DEFAULT`:

```bash
# Option 1: Maximum memory (kyuz0 toolboxes - 124GB GPU, 4GB OS)
amd_iommu=off              # May improve perf (unverified, see experiment-kernel-config.md)
amdgpu.gttsize=126976      # 124GB GTT size
ttm.pages_limit=32505856   # 124GB in pages (4KB pages)

# Option 2: Alternative full allocation (~128GB GPU)
amd_iommu=off              # May improve perf (unverified, see experiment-kernel-config.md)
amdgpu.gttsize=131072      # 128GB GTT size
ttm.pages_limit=33554432   # ~128GB in pages
amdgpu.cwsr_enable=0       # Fix MES hangs (add if needed)
```

### Model Capacity Guide

| Model | Size | Status |
|-------|------|--------|
| 70B Q4_K | ~37 GiB | ✅ Comfortable |
| 109B MoE (Llama 4 Scout) | ~58 GiB | ✅ Works well |
| 235B MoE Q3_K | ~97 GiB | ⚠️ Near limit |

**VRAM Estimation** (using kyuz0's `gguf-vram-estimator.py`):

```bash
# Llama-4-Scout 17B Q4_K at different context lengths
# 4K context:  61.6 GB
# 32K context: 74.8 GB
# 1M context:  108.8 GB

# Qwen3-235B Q3_K (97 GiB model)
# 4K context:  ~97 GiB
# 32K context: ~110 GiB
# 130K context: ~130 GiB max on 128GB system
```

## Performance Baseline

### Measured Performance

| Workload | Achieved | Theoretical | Utilization |
|----------|----------|-------------|-------------|
| GEMM (hipBLASLt, native gfx1151) | 36.9 TFLOPS | 59.4 TFLOPS | 62% |
| GEMM (HSA_OVERRIDE gfx1100) | 30.9 TFLOPS | 59.4 TFLOPS | 52% |
| GEMM (rocBLAS only) | 5.1 TFLOPS | 59.4 TFLOPS | 9% |
| Flash Attention | ~1 TFLOPS | - | Poor |

### llama.cpp Benchmarks (Llama-2-7B Q4_0, pp512/tg128)

| Backend | Prompt (t/s) | Generation (t/s) | Notes |
|---------|--------------|------------------|-------|
| Vulkan AMDVLK | **884** | 53 | Best prompt processing |
| Vulkan RADV | 729 | **55** | Slightly better tg, more stable |
| ROCm HIP baseline | 349 | 49 | Without optimizations |
| ROCm + rocWMMA + FA | 344 | 51 | Better at long context |
| CPU only | 294 | 29 | Fallback |

**Key Finding**: Vulkan outperforms ROCm 2-2.5x for prompt processing in most scenarios.

---

**Back to**: [KNOWLEDGE_BASE.md](../KNOWLEDGE_BASE.md)
