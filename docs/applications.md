# Applications and Software Support

> **Last Updated**: January 2026

## Linux Distribution Recommendations

### Fedora 43 (Recommended)

| Aspect | Status |
|--------|--------|
| Default kernel | 6.17.x ✅ |
| ROCm install | `dnf install rocm-hip-devel` |
| Firmware | Recent, fewer issues |
| Community guides | Extensive |
| Setup complexity | **Low** |

### Ubuntu 24.04

| Aspect | Status |
|--------|--------|
| Default kernel | 6.8 ❌ (need OEM 6.14+) |
| ROCm install | Manual amdgpu-install |
| Firmware | Outdated, needs AMD packages |
| Community guides | Limited |
| Setup complexity | **Medium-High** |

**Recommendation**: Use Fedora 43 for easier setup and better kernel support.

## Application Support

### llama.cpp

| Backend | Status | Build Command |
|---------|--------|---------------|
| Vulkan | ✅ Best for general use | `-DGGML_VULKAN=ON` |
| ROCm HIP | ✅ Working | `-DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151` |
| ROCm + rocWMMA | ⚠️ Deprecated | Standard kernels now faster (kyuz0 removed rocWMMA builds Jan 2026) |

**Critical Flags**:
```bash
--no-mmap     # REQUIRED - mmap catastrophically slow on ROCm
-ngl 999      # Load all layers to GPU
-fa 1         # Enable Flash Attention
```

⚠️ **WARNING**: Running without `--no-mmap` and `-fa 1` on Strix Halo can cause:
- Severe performance degradation (10-100x slower)
- Kernel crashes and GPU hangs
- Memory access violations

**Pre-built Binaries**:
- **AMD official**: `repo.radeon.com/rocm/llama.cpp/linux/`
- **Lemonade**: `github.com/lemonade-sdk/llamacpp-rocm/releases`
- **kyuz0 toolboxes**: `github.com/kyuz0/amd-strix-halo-toolboxes`

### Ollama

```bash
# Supported since v0.6.2
# Use Vulkan for stability
OLLAMA_VULKAN=1 ollama serve
```

**Known Issues**: Output corruption after 4-5 turns with ROCm

### vLLM

```bash
# Official support via PR #25908 (October 2025)
# Use Docker for easiest setup
docker run -it --privileged --device=/dev/kfd --device=/dev/dri \
  rocm/vllm-dev:rocm6.4.1_navi_ubuntu24.04_py3.12_pytorch_2.7_vllm_0.8.5

# Or kyuz0's gfx1151-specific build
docker.io/kyuz0/vllm-therock-gfx1151:latest
```

### whisper.cpp

```bash
# Confirmed working with ROCm 7.0.1+
cmake .. -DGPU_TARGETS="gfx1151" -DGGML_HIP=ON \
  -DCMAKE_C_COMPILER=/opt/rocm/bin/amdclang \
  -DCMAKE_CXX_COMPILER=/opt/rocm/bin/amdclang++
```

**Performance**:
- ~1 second per minute of audio with base.en model
- **58x speedup**: 34 min audio → 35 sec processing
- Setup: Ubuntu 25.04, ROCm 7.0.1, ggml-base.en.bin model

### pyannote-audio (Speaker Diarization)

**Status**: ✅ Works with PyTorch ROCm - GPU acceleration available

pyannote-audio is an open-source PyTorch toolkit for speaker diarization (identifying "who spoke when").

**Installation**:
```bash
# Install PyTorch with ROCm support first
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.2

# Install pyannote-audio
pip install pyannote.audio
```

**ROCm Compatibility**:
- **ROCm 6.1+**: Officially tested by AMD
- **ROCm 6.4.4**: Stable (may need `HSA_OVERRIDE_GFX_VERSION=11.0.0`)
- **ROCm 7.2**: Native gfx1151 support (recommended)
- **scottt/TheRock wheels**: Self-contained PyTorch 2.7 with native gfx1151

**Available Models**:

| Model | Version | Released | Status |
|-------|---------|----------|--------|
| `speaker-diarization-community-1` | pyannote 4.0+ | Sept 2025 | **Recommended** |
| `speaker-diarization-3.1` | pyannote 3.4.0 | Sept 2025 | **Stable** |

**Usage Example**:
```python
from pyannote.audio import Pipeline
import torch

# Load pipeline (requires HuggingFace token)
pipeline = Pipeline.from_pretrained(
    "pyannote/speaker-diarization-community-1",
    use_auth_token="hf_your_token_here"
)

# Move to GPU for speed
pipeline.to(torch.device("cuda"))

# Run diarization
diarization = pipeline("audio.wav")

# Print results
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f"[{turn.start:.1f}s - {turn.end:.1f}s] {speaker}")
```

**Performance**:
- Voice Activity Detection: Can run on CPU (fast either way)
- **Speaker embeddings**: GPU provides ~10-50x speedup over CPU
- Clustering/assignment: CPU (lightweight)

**Requirements**:
- Python 3.10+
- FFmpeg (for audio decoding)
- HuggingFace token (models are gated)

**Critical Runtime Flags** (when using containers):
- `--ipc=host` - Required for ROCm on Strix Halo (unified memory)
- `--device=/dev/kfd --device=/dev/dri` - GPU access

## Turnkey Solutions

### kyuz0 Strix Halo Toolboxes (Recommended)

**Best for**: llama.cpp inference on Strix Halo

**Project**: `docker.io/kyuz0/amd-strix-halo-toolboxes`

**Available Images**:

| Tag | Backend | ROCm Version | Notes |
|-----|---------|--------------|-------|
| `vulkan-radv` | Vulkan (RADV) | N/A | **Most stable, recommended** |
| `vulkan-amdvlk` | Vulkan (AMDVLK) | N/A | Fastest but limited to 2GB allocations |
| `rocm-6.4.4` | HIP | 6.4.4 | Stable with good performance |
| `rocm-7.1.1` | HIP | 7.1.1 | Current GA release |
| `rocm-7.2` | HIP | 7.2 | RHEL10-based build |
| `rocm7-nightlies` | HIP | 7.x nightly | Bleeding-edge patches |

**Tested Configuration**:
- Host OS: Fedora 42/43
- Kernel: 6.18.3-200
- Firmware: 20251111
- **⚠️ AVOID**: Firmware 20251125 (breaks ROCm - AMD recalled)

**Quick Start (Vulkan - Recommended)**:
```bash
toolbox create llama-vulkan-radv \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv \
  -- --device /dev/dri --group-add video --security-opt seccomp=unconfined

toolbox enter llama-vulkan-radv
llama-cli --no-mmap -ngl 999 -fa 1 -m model.gguf
```

**Quick Start (ROCm)**:
```bash
toolbox create llama-rocm-7.1.1 \
  --image docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.1.1 \
  -- --device /dev/dri --device /dev/kfd \
  --group-add video --group-add render --group-add sudo \
  --security-opt seccomp=unconfined

toolbox enter llama-rocm-7.1.1
llama-cli --no-mmap -ngl 999 -fa 1 -m model.gguf
```

**Included Tools**:
- `refresh-toolboxes.sh` - Auto-update containers with correct GPU flags
- `gguf-vram-estimator.py` - Calculate VRAM needs at various context lengths
- `run_distributed_llama.py` - RPC-based distributed inference across clusters

**Interactive Benchmarks**: https://kyuz0.github.io/amd-strix-halo-toolboxes/

**Important Notes** (January 2026):
- **rocWMMA removed**: Standard kernels now faster than rocWMMA builds
- **refresh-toolboxes.sh**: Auto-pulls latest images with correct GPU access flags

**Ubuntu 24.04 Users**: Standard `toolbox` package breaks GPU access. Use `distrobox` instead with same device flags.

### Ryzers (AMD Research Docker Framework)

```bash
git clone https://github.com/AMDResearch/Ryzers
pip install Ryzers/
ryzers build ollama    # or llamacpp, genesis, sam, etc
ryzers run
```

**Available Packages**:

| Category | Packages |
|----------|----------|
| NPU | xdna, iron, npueval, ryzenai_cvml |
| LLM | ollama, llamacpp, lmstudio |
| VLM | Gemma3, SmolVLM, Phi-4, LFM2-VL |
| Vision | OpenCV, SAM, MobileSAM, DINOv3 |
| Robotics | ROS 2, Gazebo, LeRobot |

### Ryzen AI SDK 1.6.1 (Official Linux Support)

Download from AMD Early Access Lounge, then:

```bash
# Install .deb packages (Ubuntu 24.04)
sudo apt install ./xrt_*-amd64-base.deb ./xrt_*-amd64-npu.deb ./xrt_plugin*-amdxdna.deb

# Create venv and verify
python3.10 -m venv ~/ryzen_ai_venv
source ~/ryzen_ai_venv/bin/activate
cd quicktest && python quicktest.py
```

### GAIA (AMD's Agent Framework)

```bash
pip install gaia-cli
gaia --help
```

**Caveat**: Linux = Vulkan/iGPU only, NPU hybrid mode is Windows-only.

### NPU vs GPU for LLM Inference

**From AMD Lemonade developer** (https://github.com/lemonade-sdk/lemonade/issues/5#issuecomment-3096694964):

> "On Strix Halo I would not expect a performance benefit from NPU vs. GPU. On that platform I would suggest using the NPU for LLMs when the GPU is already busy with something else, for example the NPU runs an AI gaming assistant while the GPU runs the game."

**Takeaway**: Don't expect NPU to speed up LLM inference. Use NPU when GPU is occupied with other workloads (gaming, rendering, etc.).

### Lemonade Server (AMD Official)

| Resource | URL |
|----------|-----|
| Main site | https://lemonade-server.ai/ |
| FAQ/Docs | https://lemonade-server.ai/docs/faq/ |
| GitHub | https://github.com/lemonade-sdk/lemonade |
| ROCm llama.cpp | https://github.com/lemonade-sdk/llamacpp-rocm |

### Turnkey Recommendation Matrix

| Use Case | Best Solution |
|----------|---------------|
| **LLM inference (llama.cpp)** | **kyuz0 toolboxes** |
| LLM chat (general) | Ryzers ollama or llamacpp |
| Object detection | Ryzers npueval or ryzenai_cvml |
| STT/Whisper | Ryzen AI SDK + pre-quantized models |
| Computer Vision | Ryzers sam, mobilesam, dinov3 |
| PyTorch Research | scottt/rocm-TheRock wheels |
| Distributed LLM | kyuz0 toolboxes + run_distributed_llama.py |

### Reference Dockerfiles for gfx1151

**weiziqian/rocm_pytorch_docker_gfx1151** - Proven working config:

```dockerfile
FROM docker.io/rocm/dev-ubuntu-24.04:6.4.3-complete

ENV CMAKE_PREFIX_PATH=/opt/rocm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common build-essential ninja-build

# Python 3.11 from deadsnakes
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get install -y python3.11 python3.11-dev python3.11-venv

RUN python3.11 -m venv /root/venv
ENV PATH="/root/venv/bin:$PATH"

# scottt's gfx1151 wheels - KNOWN WORKING
RUN pip install "https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl"
RUN pip install "numpy<2.0"
```

**scottt/rocm-TheRock Wheel URLs** (gfx1151):

| Package | Python | URL |
|---------|--------|-----|
| torch 2.7.0a0 | 3.11 Linux | `https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl` |
| torch 2.7.0a0 | 3.12 Windows | `https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+git3f903c3-cp312-cp312-win_amd64.whl` |
| torchvision 0.22.0 | 3.12 Windows | `https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torchvision-0.22.0+9eb57cd-cp312-cp312-win_amd64.whl` |

---

**Back to**: [KNOWLEDGE_BASE.md](../KNOWLEDGE_BASE.md)
