# ROCm Support for AMD Strix Halo

> **Status**: Preview support in ROCm 6.4.4; full official support expected Q2 2026 with ROCm 7.2.2

## Official Support Timeline

| Version | Status | Notes |
|---------|--------|-------|
| ROCm 6.4.4 | ✅ Preview/Stable | **AMD's stable stepping stone**; PyTorch support on Windows/Linux |
| ROCm 6.5.0rc | ⚠️ Community | scottt's self-contained wheels (no system ROCm needed) |
| ROCm 7.0.x | ⚠️ Regressions | Some models slower than 6.4.4 |
| ROCm 7.1.1 | ⚠️ Batch norm bug | [ROCm#5339](https://github.com/ROCm/ROCm/issues/5339) reported issues |
| ROCm 7.2.0 | ✅ Released | Counter collection for gfx1150/gfx1151; rocWMMA gfx1150 support; JAX 0.8.0 |
| ROCm 7.2.2 | 🔜 Q2 2026 | Full official support with AMD's "Ryzen AI Halo" dev kit |
| TheRock 7.11 | ✅ Nightlies | **Best native gfx1151 support**; 2x faster transformers vs gfx1100 fallback |

**AMD Official Statement** ([ROCm#5339](https://github.com/ROCm/ROCm/issues/5339)):
> "The 6.4.4 PyTorch releases are stepping stones to getting full support with ROCm 7.x + Strix Halo."

## Library Support

| Library | Status | Notes |
|---------|--------|-------|
| rocBLAS | ✅ Full | gfx1151 TensileLibraries included |
| hipBLASLt | ✅ Full | `ROCBLAS_USE_HIPBLASLT=1` for better perf |
| rocWMMA | ✅ Added | Via PR #538; needed for Flash Attention |
| AOTriton | ⚠️ Experimental | Custom builds required for FA |
| MIOpen | ⚠️ Partial | Some convolution issues |

## TheRock Nightlies

For best compatibility with latest kernels, use TheRock nightly builds:

```bash
# Download gfx1151 nightly tarball
https://github.com/ROCm/TheRock/releases/

# Untar to any folder (e.g., /opt/rocm or ~/therock/rocm-7.0)
tar xf rocm-*.tar.xz -C ~/therock/
```

**Environment Setup Script** (required to use extracted tarball):

```bash
# ---- ROCm nightly from extracted tarball ----
export ROCM_PATH=$HOME/therock/rocm-7.0  # adjust to your path
export HIP_PLATFORM=amd
export HIP_PATH=$ROCM_PATH
export HIP_CLANG_PATH=$ROCM_PATH/llvm/bin
export HIP_INCLUDE_PATH=$ROCM_PATH/include
export HIP_LIB_PATH=$ROCM_PATH/lib
export HIP_DEVICE_LIB_PATH=$ROCM_PATH/lib/llvm/amdgcn/bitcode

# Search paths -- prepend
export PATH="$ROCM_PATH/bin:$HIP_CLANG_PATH:$PATH"
export LD_LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:$ROCM_PATH/llvm/lib:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:${LIBRARY_PATH:-}"
export CPATH="$HIP_INCLUDE_PATH:${CPATH:-}"
export PKG_CONFIG_PATH="$ROCM_PATH/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
```

**Compiling llama.cpp with ROCm 7.0 Nightlies**:

One HIP_VERSION change is required - see: https://www.reddit.com/r/LocalLLaMA/comments/1m6b151/comment/n4jlc3z

## Critical Environment Variables

```bash
# REQUIRED for stability
export HSA_ENABLE_SDMA=0                    # Fix checkerboard artifacts

# For PyTorch (IMPORTANT: disable hipBLASLt for better performance!)
export PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"
export ROCBLAS_USE_HIPBLASLT=0              # +20% GEMM performance on Strix Halo
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1

# For llama.cpp (hipBLASLt may help or hurt - benchmark your model)
# export ROCBLAS_USE_HIPBLASLT=1            # Test both 0 and 1
```

> ⚠️ **SoftAb finding**: `ROCBLAS_USE_HIPBLASLT=0` improves PyTorch GEMM by ~20% on Strix Halo (32.7 vs 27.2 TFLOPS). This contradicts some older guidance recommending hipBLASLt=1.

## Backend Performance Comparison

### When to Use Each Backend

| Use Case | Recommended Backend |
|----------|---------------------|
| General inference | Vulkan (AMDVLK for pp, RADV for stability) |
| Long context (8K+) | ROCm + rocWMMA + FA |
| PyTorch training | ROCm (TheRock nightlies) |
| Maximum stability | Vulkan RADV |
| Windows | Vulkan (ROCm not well supported) |

**Important**: Best backend for prompt processing (pp) often differs from best for token generation (tg). If optimizing for a specific workload, benchmark both phases separately. Different backends also have different performance decay characteristics as context length grows - some have higher peak but drop off faster at long context.

### Strix Halo vs DGX Spark Performance

**Token Generation (Vulkan AMDVLK)** - gpt-oss-120b Q8/MXFP4:

| Context | DGX Spark | Strix Halo | Spark Advantage |
|---------|-----------|------------|-----------------|
| 2K | 52.87 | 50.05 | +5.6% |
| 8K | 48.46 | 43.15 | +12.3% |
| 32K | 38.76 | 31.54 | +22.9% |

**Token Generation (ROCm + rocWMMA, lhl tuned)**:

| Context | DGX Spark | Strix Halo | Spark Advantage |
|---------|-----------|------------|-----------------|
| 2K | 52.87 | 48.97 | +8.0% |
| 8K | 48.46 | 43.55 | +11.3% |
| 32K | 38.76 | 36.43 | **+6.4%** |

**Key Insight**: lhl's tuned rocWMMA branch significantly improves long-context performance, closing the gap with DGX Spark.

### Model Size Performance (llama.cpp)

Performance varies by model size on Strix Halo's unified memory architecture:

| Model | Size | Backend | pp512 (t/s) | Notes |
|-------|------|---------|-------------|-------|
| TinyLlama 1.1B Q4_K_M | ~0.6 GiB | Vulkan RADV | 5369 | Small models = highest t/s |
| Llama 2 7B Q4_0 | ~3.5 GiB | Vulkan RADV | 908-1012 | Mid-size models (FA impact visible) |
| Qwen3MoE 30B Q5_K | ~20 GiB | Vulkan AMDVLK | 525-735 | Large models (context-dependent) |

**Key Insight**: Smaller models achieve much higher tokens/sec due to less memory bandwidth, better cache utilization, and reduced compute per token.

## PyTorch ROCm Compatibility

### Installation Options

```bash
# Option 1: gfx1151-specific nightlies (recommended)
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ --pre torch torchaudio torchvision

# Option 2: Official ROCm wheels
pip install torch torchvision torchaudio -f https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1.1/

# Option 3: scottt/rocm-TheRock wheels (recommended for CV work)
pip install "https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl"
```

### Compatibility Matrix

| Source | Version | Native gfx1151? | hipBLASLt | Peak TFLOPS | Notes |
|--------|---------|-----------------|-----------|-------------|-------|
| PyPI rocm6.2 | 2.5.1+rocm6.2 | ❌ Fails | N/A | 0 | "invalid device function" |
| PyPI rocm6.2 + HSA_OVERRIDE | 2.5.1+rocm6.2 | ⚠️ gfx1100 fallback | Disabled | 25.6 (43%) | Works but suboptimal |
| TheRock 7.11 | 2.11.0a0 | ✅ Native gfx1151 | **Disabled** | **32.7 (55%)** | Best config - disable hipBLASLt! |
| TheRock 7.11 + hipBLASLt | 2.11.0a0 | ✅ Native gfx1151 | Enabled | 27.2 (46%) | hipBLASLt hurts performance |

**Key Findings** (SoftAb benchmark 2026-02-02):
- Official PyTorch wheels from `download.pytorch.org/whl/rocm6.2` do NOT include gfx1151 kernels
- **hipBLASLt hurts performance on Strix Halo** - disable with `ROCBLAS_USE_HIPBLASLT=0`
- TheRock 7.11 with native gfx1151 is 20% faster on GEMM vs gfx1100 fallback
- **Transformer models (ViT, BERT) are 2x faster** on native gfx1151 vs gfx1100 fallback

### Neural Network Throughput (batch=32, FP16)

| Model | TheRock gfx1151 | ROCm 6.2 gfx1100 | Speedup |
|-------|-----------------|------------------|---------|
| ResNet-18 | 4697 img/s | 4665 img/s | 1.0x |
| ResNet-50 | 1083 img/s | 1085 img/s | 1.0x |
| **ViT-B/16** | **725 img/s** | 317 img/s | **2.3x** |
| **BERT-base (seq=128)** | **1193 seq/s** | 709 seq/s | **1.7x** |
| **BERT-base (seq=512)** | **271 seq/s** | 125 seq/s | **2.2x** |

**Key Insight**: CNNs perform similarly, but **attention-based models are 2x faster on native gfx1151**.

> 📊 **Full benchmark data**: See [docker/pytorch/BENCHMARKS.md](../docker/pytorch/BENCHMARKS.md) for complete results, image compatibility matrix, and recommended configurations.

### HSA_OVERRIDE Workaround

```bash
# Forces gfx1100 kernels - WORKS but with caveats
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export HSA_ENABLE_SDMA=0

# Results in: 30.9 TFLOPS (52% utilization)
# Warning: hipBLASLt disabled, may crash on long runs
```

⚠️ **Not recommended for production** - causes eventual MES/kernel errors.

### Known PyTorch Issues

1. **Official wheels lack gfx1151** - Use TheRock nightlies or build from source
2. **Flash Attention fails** with "not compiled for gfx1151" - requires AOTriton custom build
3. ~~**Native gfx1151 kernels 2-6x slower** than gfx1100~~ **OUTDATED** - TheRock 7.11 gfx1151 is now **2x faster** for transformers (see benchmarks above)
4. **90-95% time in hipMemcpyWithStream** for LLM decode (tracked: pytorch/pytorch#171687)
5. **HSA_OVERRIDE causes eventual MES errors** - Not recommended for production

### Building PyTorch with AOTriton (Flash Attention)

```bash
# Clone lhl's build scripts
git clone https://github.com/lhl/strix-halo-testing
cd strix-halo-testing/torch-therock

# Follow setup script
./00-setup-env.sh

# Build with AOTriton
export PYTORCH_ROCM_ARCH="gfx1151"
export USE_AOTRITON=1 BUILD_AOTRITON=1
```

## Triton/AOTriton Support

### Current Status

- **OpenAI Triton**: Experimental gfx1151 support
- **AOTriton 0.10b+**: Experimental gfx1151 support
- **Official Docker images**: Exclude gfx1151 architecture

### Working Builds

- **scottt's Windows branch**: `github.com/scottt/aotriton/commits/gfx1151-therock/`
- **kyuz0 containers**: `docker.io/kyuz0/vllm-therock-gfx1151`
- **lhl's PyTorch builds**: `github.com/lhl/strix-halo-testing/tree/main/torch-therock`

## Vulkan Compute

### Driver Comparison

| Driver | Optimal `-ub` | Prompt (pp) | Generation (tg) | Stability |
|--------|---------------|-------------|-----------------|-----------|
| AMDVLK | 512 | **Better** | Good | Good |
| Mesa RADV | 1024 | Lower | **Better** | **Best** |

### Driver Selection

```bash
# Use RADV explicitly
AMD_VULKAN_ICD=RADV llama-cli ...

# Use AMDVLK (default when both installed)
llama-cli ...
```

### Vulkan Projects

| Project | Notes |
|---------|-------|
| llama.cpp | Mature Vulkan backend, KHR_coopmat support |
| Kompute | Linux Foundation GPU compute framework |
| Ollama | `OLLAMA_VULKAN=1` for Vulkan mode |
| LM Studio | Vulkan works (ROCm broken on gfx1151) |

---

**Back to**: [KNOWLEDGE_BASE.md](../KNOWLEDGE_BASE.md)
