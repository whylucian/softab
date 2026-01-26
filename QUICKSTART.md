# SoftAb Quick Start

**Stop fighting dependency hell. Test what works automatically.**

AMD Strix Halo's software stack changes constantly. Instead of manually troubleshooting why ROCm broke after a kernel upgrade, test all configurations systematically and document what works.

## Prerequisites

- AMD Ryzen AI Max+ 395 (Strix Halo) with Radeon 8060S
- Fedora 43 (or Ubuntu 24.04 with kernel 6.16+)
- Podman or Docker installed
- **Expect things to fail** - that's valuable data

## 10-Minute Single Test

Run a quick test with a pre-built image:

```bash
# Download a small test model
mkdir -p /data/models
cd /data/models
huggingface-cli download TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF \
  tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Build a test image (or pull pre-built)
podman build -t softab:llama-vulkan-radv \
  -f docker/llama-cpp/Dockerfile.vulkan-radv .

# Run simple test
./benchmarks/llama-simple.sh \
  softab:llama-vulkan-radv \
  /data/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Expected: "Hello! How can I assist you today?"
```

## 15-Minute Experiment

Create your first ablation experiment:

```bash
# 1. Create experiment from template
cp -r experiments/TEMPLATE experiments/$(date +%Y-%m-%d)_first-test
cd experiments/$(date +%Y-%m-%d)_first-test

# 2. Record system environment (non-mutable variables)
./record-environment.sh > ENVIRONMENT.txt

# 3. Choose images to test (edit run-all-benchmarks.sh)
# Example: Compare Vulkan RADV vs AMDVLK
nano run-all-benchmarks.sh
# Set IMAGES array:
#   IMAGES=(
#     "softab:llama-vulkan-radv"
#     "softab:llama-vulkan-amdvlk"
#   )

# 4. Run benchmarks
./run-all-benchmarks.sh

# Results saved to raw_results/
# - llama-simple.log (does it work?)
# - llama-bench.log (how fast?)

# 5. Analyze with LLM
# "Analyze these benchmark logs and tell me which driver performs better"
```

## Common Tasks

### Build an Image

```bash
# Use the canonical builder
cd /home/tc/softab
./docker/build-matrix.sh list               # Show all available images
./docker/build-matrix.sh build-llama        # Build all llama.cpp variants

# Or build manually
podman build -t softab:llama-hip-rocm72 \
  -f docker/llama-cpp/Dockerfile.hip-rocm72 \
  --build-arg GFX_TARGET=gfx1151 .
```

### List Available Images

```bash
podman images | grep softab
```

### Run a Benchmark

```bash
# Simple test (does it work?)
./benchmarks/llama-simple.sh IMAGE MODEL_PATH

# Performance test (how well?)
./benchmarks/llama-bench.sh IMAGE MODEL_PATH

# PyTorch GEMM benchmark
./benchmarks/pytorch-gemm.sh IMAGE
```

### Download Models

```bash
# Use the helper script
./scripts/download-models.sh

# Or manually with huggingface-cli
pip install huggingface-hub[cli]
huggingface-cli download REPO_NAME FILENAME --local-dir /data/models
```

### Run Specific Ablation Tests

```bash
# Test Flash Attention impact
./scripts/ablation-flash-attention.sh /data/models/model.gguf

# Test Vulkan batch size tuning
./scripts/ablation-vulkan-batch-size.sh RADV /data/models/model.gguf

# Test container runtime flags
./scripts/ablation-container-flags.sh softab:llama-hip-rocm72 /data/models/model.gguf
```

## Troubleshooting

### GPU Not Detected

```bash
# Check GPU visibility
rocminfo | grep gfx
lspci | grep VGA

# Ensure kernel 6.16.9+ for VRAM visibility
uname -r

# Check firmware version
rpm -q linux-firmware
# Avoid linux-firmware-20251125 (broken)
```

### "Invalid Device Function" Error

```bash
# Likely missing gfx1151 kernels
# Solution: Use TheRock nightlies or set HSA_OVERRIDE (not recommended)
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export HSA_ENABLE_SDMA=0
```

### Container Permission Denied

```bash
# Ensure correct device access
podman run --device=/dev/kfd --device=/dev/dri \
  --ipc=host \
  --security-opt label=disable \
  IMAGE_NAME

# On Fedora, SELinux may block GPU access
# Workaround: --security-opt label=disable
```

### Slow Performance

```bash
# Check GPU clock speed
cat /sys/class/drm/card0/device/pp_dpm_sclk

# Force high performance mode
echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Verify SDMA is disabled
echo $HSA_ENABLE_SDMA  # Should be 0
```

## Next Steps

- Read [README.md](README.md) for full methodology
- Check [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) for community findings
- See [experiments/README.md](experiments/README.md) for detailed experiment workflow
- Join the community: [strixhalo.wiki](https://strixhalo.wiki)

## Decision Tree: Is SoftAb Right For You?

**Use SoftAb if you want to answer:**
- Does ROCm 7.2 work better than 6.4.4 on Strix Halo?
- Is Vulkan RADV or AMDVLK faster for llama.cpp?
- Which GFX target (gfx1100/1150/1151/1152) performs best?
- Do environment variables like HSA_ENABLE_SDMA affect performance?

**Don't use SoftAb if you want to answer:**
- Which LLM is best? (Llama vs Qwen vs Phi) → Use [llm-tracker.info](https://llm-tracker.info)
- What quantization method is fastest? (Q4_K_M vs Q5_0) → Out of scope
- What batch size optimizes latency? → Out of scope
- How do different prompt lengths affect speed? → Out of scope

SoftAb focuses on **software stack configuration**, not model comparisons or inference tuning.
