# SoftAb Toolbox Images

Fedora Toolbox/Distrobox compatible containers for Strix Halo development, inspired by [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes).

## What are Toolboxes?

Toolboxes are containerized development environments that integrate seamlessly with your host system:
- Share home directory with host
- Access host GPU devices
- Preserve user permissions
- Work like native environment

## Available Toolboxes

### 1. llama.cpp Vulkan (RADV) - **Recommended for LLM Inference**

**Performance**: 5369 t/s prompt processing (best in SoftAb ablations)

```bash
# Build
podman build -t softab-toolbox:llama-vulkan-radv \
  -f docker/toolbox/Dockerfile.llama-vulkan-radv .

# Create toolbox
toolbox create llama-vulkan \
  --image localhost/softab-toolbox:llama-vulkan-radv \
  -- --device /dev/dri --group-add video --security-opt seccomp=unconfined

# Enter
toolbox enter llama-vulkan

# Run (with automatic critical flags)
llama-run /path/to/model.gguf

# Benchmark
llama-bench-run /path/to/model.gguf
```

### 2. llama.cpp ROCm 7.2 HIP

**Performance**: 4715 t/s prompt processing (native gfx1151)

**CRITICAL**: Requires `--ipc=host` for Strix Halo unified memory!

```bash
# Build
podman build -t softab-toolbox:llama-rocm72 \
  -f docker/toolbox/Dockerfile.llama-rocm72 .

# Create toolbox (note --ipc=host)
toolbox create llama-rocm \
  --image localhost/softab-toolbox:llama-rocm72 \
  -- --device /dev/dri --device /dev/kfd \
     --ipc=host \
     --group-add video --group-add render

# Enter and build llama.cpp
toolbox enter llama-rocm
build-llama

# Run
llama-run /path/to/model.gguf
```

### 3. PyTorch with ROCm - **Best for ML Training**

**Performance**: 36.27 TFLOPS (SoftAb optimal configuration)

```bash
# Build
podman build -t softab-toolbox:pytorch-fedora \
  -f docker/toolbox/Dockerfile.pytorch-fedora .

# Create toolbox
toolbox create pytorch \
  --image localhost/softab-toolbox:pytorch-fedora \
  -- --device /dev/dri --device /dev/kfd

# Enter
toolbox enter pytorch

# Activate environment (auto-loads optimal env vars)
source /etc/profile.d/pytorch-strix-halo.sh

# Run benchmark
pytorch-bench

# Start Jupyter
jupyter notebook --ip=0.0.0.0 --no-browser
```

### 4. whisper.cpp Vulkan (RADV) - **Recommended for Speech Recognition**

**Performance**: ~58x realtime (comparable to HIP)

```bash
# Build
podman build -t softab-toolbox:whisper-vulkan-radv \
  -f docker/toolbox/Dockerfile.whisper-vulkan-radv .

# Create toolbox
toolbox create whisper-vulkan \
  --image localhost/softab-toolbox:whisper-vulkan-radv \
  -- --device /dev/dri --group-add video --security-opt seccomp=unconfined

# Enter
toolbox enter whisper-vulkan

# Download model (if needed)
whisper-download-model base.en /data/models

# Run transcription
whisper-run /data/models/ggml-base.en.bin /path/to/audio.wav

# Benchmark
whisper-bench-run /data/models/ggml-base.en.bin /path/to/audio.wav
```

### 5. whisper.cpp ROCm 7.2 HIP

**Performance**: 58x realtime (5.14s for 300s audio)

**CRITICAL**: Requires `--ipc=host` for Strix Halo unified memory!

```bash
# Build
podman build -t softab-toolbox:whisper-rocm72 \
  -f docker/toolbox/Dockerfile.whisper-rocm72 .

# Create toolbox (note --ipc=host)
toolbox create whisper-rocm \
  --image localhost/softab-toolbox:whisper-rocm72 \
  -- --device /dev/dri --device /dev/kfd \
     --ipc=host \
     --group-add video --group-add render

# Enter and build whisper.cpp
toolbox enter whisper-rocm
build-whisper

# Run transcription
whisper-run /data/models/ggml-base.en.bin /path/to/audio.wav
```

## Ubuntu Users (Distrobox)

Standard `toolbox` package breaks GPU access on Ubuntu 24.04. Use `distrobox` instead:

```bash
# Install distrobox
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh

# Create with distrobox (same flags as toolbox)
distrobox create --image IMAGE --name NAME -- --device /dev/dri ...
```

## Critical Flags for Strix Halo

### llama.cpp (Vulkan and HIP)

**Always use** (kyuz0 + SoftAb recommendation):
```bash
llama-cli --no-mmap -ngl 999 -fa 1 -m model.gguf
```

- `--no-mmap`: Prevents catastrophic slowdown (10-100x)
- `-ngl 999`: Load all layers to GPU
- `-fa 1`: Enable flash attention (stability)

### PyTorch

**Environment variables** (auto-loaded in toolbox):
```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0  # Required for official wheels
export HSA_ENABLE_SDMA=0                # Stability
export ROCBLAS_USE_HIPBLASLT=1          # Performance
```

### ROCm 7.2 Containers

**Must use** `--ipc=host`:
```bash
toolbox create ... -- --ipc=host --device=/dev/kfd --device=/dev/dri
```

Without this flag: `Memory critical error by agent node-0`

## Comparison: Toolbox vs Regular Containers

| Feature | Toolbox | Podman Run |
|---------|---------|------------|
| Home directory | Shared | Isolated |
| User ID | Preserved | May differ |
| System integration | Seamless | Manual |
| Best for | Development | Testing/CI |
| Host access | Full | Limited |

## Performance Expectations

Based on SoftAb ablation study (101 configurations tested):

| Workload | Backend | Performance | Notes |
|----------|---------|-------------|-------|
| llama.cpp pp512 | Vulkan RADV | **5369 t/s** | Best overall |
| llama.cpp pp512 | HIP ROCm 7.2 | 4715 t/s | Better for long context |
| llama.cpp tg32 | Vulkan RADV | 245 t/s | Token generation |
| PyTorch GEMM | Fedora ROCm | **36.27 TFLOPS** | 62% of peak |
| whisper.cpp | HIP ROCm 7.2 | **58x realtime** | 5.14s for 300s audio |
| whisper.cpp | Vulkan RADV | ~58x realtime | Similar to HIP |

## Helper Scripts in Containers

Each toolbox includes helper scripts:

### llama.cpp Vulkan
- `llama-run` - Run with critical flags automatically
- `llama-bench-run` - Benchmark with SoftAb test configuration

### llama.cpp ROCm
- `build-llama` - Build llama.cpp with ROCm
- `llama-run` - Run with critical flags + ROCm env

### whisper.cpp Vulkan
- `whisper-run` - Run transcription
- `whisper-bench-run` - Benchmark with timing output
- `whisper-download-model` - Download whisper models from HuggingFace

### whisper.cpp ROCm
- `build-whisper` - Build whisper.cpp with ROCm (run after toolbox creation)
- `whisper-run` - Run transcription
- `whisper-bench-run` - Benchmark with timing output
- `whisper-download-model` - Download whisper models from HuggingFace

### PyTorch
- `pytorch-bench` - Run GEMM benchmark (4096x4096 FP16)
- `/etc/profile.d/pytorch-strix-halo.sh` - Environment setup

## Troubleshooting

### "Memory critical error"
- **Cause**: Missing `--ipc=host` flag (ROCm 7.2 only)
- **Fix**: Recreate toolbox with `--ipc=host`

### GPU not detected
- **Cause**: Missing device flags
- **Fix**: Add `--device /dev/dri --device /dev/kfd` (HIP) or `--device /dev/dri` (Vulkan)

### Slow performance
- **llama.cpp**: Check using `--no-mmap -ngl 999 -fa 1`
- **PyTorch**: Check env vars with `echo $HSA_OVERRIDE_GFX_VERSION`

### Video group access denied
- **Cause**: User not in video group in toolbox
- **Fix**: `sudo usermod -a -G video,render $USER` inside toolbox

## Reference

- **SoftAb FINDINGS.md**: Complete ablation results (101 configs)
- **SoftAb KNOWLEDGE_BASE.md**: Community findings and optimizations
- **kyuz0 toolboxes**: https://github.com/kyuz0/amd-strix-halo-toolboxes
- **Toolbox docs**: https://containertoolbx.org/
- **Distrobox docs**: https://github.com/89luca89/distrobox

## Build All Toolboxes

```bash
# Build all at once (5 toolboxes)
for df in docker/toolbox/Dockerfile.*; do
    name=$(basename $df | sed 's/Dockerfile.//')
    echo "Building softab-toolbox:$name..."
    podman build -t softab-toolbox:$name -f $df .
done

# Available toolboxes after build:
# - softab-toolbox:llama-vulkan-radv
# - softab-toolbox:llama-rocm72
# - softab-toolbox:pytorch-fedora
# - softab-toolbox:whisper-vulkan-radv
# - softab-toolbox:whisper-rocm72
```
