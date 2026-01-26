# Community Resources and References

> **Active community maintaining Strix Halo AI software stack**

## Primary Documentation

| Resource | URL | Focus |
|----------|-----|-------|
| Strix Halo Wiki | https://strixhalo.wiki | Comprehensive setup guides |
| lhl's testing repo | https://github.com/lhl/strix-halo-testing | Benchmarks, build scripts |
| llm-tracker.info | https://llm-tracker.info/_TOORG/Strix-Halo | Deep technical documentation |
| kyuz0 toolboxes | https://github.com/kyuz0/amd-strix-halo-toolboxes | Docker containers |

## Interactive Tools

- **Benchmark viewer**: https://kyuz0.github.io/amd-strix-halo-toolboxes/
- **Framework forums**: https://community.frame.work (search "Strix Halo")
- **Discord**: https://discord.gg/pnPRyucNrG

## Key Repositories

| Repository | Purpose | Best For |
|------------|---------|----------|
| [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) | llama.cpp containers | LLM inference |
| [kyuz0/amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes) | vLLM containers | Production serving |
| [scottt/rocm-TheRock](https://github.com/scottt/rocm-TheRock) | PyTorch wheels | **CV/ML research** |
| [lhl/strix-halo-testing](https://github.com/lhl/strix-halo-testing) | Comprehensive test scripts | Benchmarking |
| [llm-tracker.info](https://llm-tracker.info/_TOORG/Strix-Halo) | Ongoing performance notes | Latest findings |
| [lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm) | Pre-built llama.cpp binaries | Quick setup |
| [hjc4869/llama.cpp](https://github.com/hjc4869/llama.cpp) | Optimized fork | David Huang's optimizations |
| nix-strix-halo | Nix flake | Reproducible builds |

> **For Computer Vision/PyTorch work**: Use `scottt/rocm-TheRock` path. The kyuz0 llama.cpp containers are LLM-focused and won't help for EfficientLoFTR, diffusion models, etc.

## Lemonade Server (AMD Official)

| Resource | URL |
|----------|-----|
| Main site | https://lemonade-server.ai/ |
| FAQ/Docs | https://lemonade-server.ai/docs/faq/ |
| GitHub | https://github.com/lemonade-sdk/lemonade |
| ROCm llama.cpp | https://github.com/lemonade-sdk/llamacpp-rocm |
| AMD Tutorial | https://www.amd.com/en/developer/resources/technical-articles/2025/ryzen-ai-radeon-llms-with-lemonade.html |

## Additional Resources

| Resource | URL |
|----------|-----|
| Ryzen AI SDK docs | https://ryzenai.docs.amd.com/en/latest/relnotes.html |
| Level1Techs benchmarks | https://forum.level1techs.com/t/strix-halo-ryzen-ai-max-395-llm-benchmark-results/233796 |
| ROCm Issue Tracker | https://github.com/ROCm/ROCm/issues |
| AMD Developer Forums | https://community.amd.com/t5/ai/ct-p/amd-ai |

## Kernel and Container Considerations

### Understanding Container Architecture

**Critical**: Containers are NOT virtual machines. They share the host kernel.

| Component | Location | Can Vary in Container? |
|-----------|----------|------------------------|
| **Kernel** | Host | ❌ NO - shared by all containers |
| **Kernel Modules** (`amdgpu`, etc.) | Host | ❌ NO - loaded in host kernel |
| **Device Files** (`/dev/kfd`, `/dev/dri`) | Host | ❌ NO - bind-mounted from host |
| **ROCm Userspace** (rocBLAS, hipBLAS) | Container | ✅ YES - part of container image |
| **Python Version** | Container | ✅ YES - isolated per container |
| **Application Binaries** | Container | ✅ YES - isolated per container |

### Why Kernel Matters for GPU Workloads

The host kernel directly impacts GPU performance and compatibility:

| Kernel Feature | Impact on Strix Halo |
|----------------|---------------------|
| `amdgpu` driver version | Determines GPU support, bug fixes |
| VRAM visibility | 6.16.9+ fixes bug showing only ~15.5GB |
| Kernel ABI | 6.18.4+ may need matching ROCm userspace |
| Memory management | GTT/GART configuration via kernel params |

### Container vs Host Components

**Container Image Contains**:
- ✅ ROCm libraries (rocBLAS, hipBLASLt, MIOpen)
- ✅ Python interpreter and packages (PyTorch, etc.)
- ✅ Application binaries (llama.cpp, whisper.cpp)
- ✅ Environment variables (HSA_OVERRIDE_GFX_VERSION, etc.)

**Host Provides**:
- ✅ Linux kernel (all containers use same kernel)
- ✅ amdgpu kernel module (GPU driver)
- ✅ Device access (/dev/kfd, /dev/dri)
- ✅ Firmware (GPU microcode)

### Kernel Ablation: Practical Limitations

**To test different kernel versions, you must**:
1. Install multiple kernels on the host
2. Reboot the host to switch kernels
3. Re-run container tests on the new kernel
4. Cannot test kernels in parallel (single host, one kernel at a time)

**Recommendation for ablation studies**: Treat kernel as a constant, not a variable. Testing kernels requires host reboots and serialized testing, which is expensive and out of scope for software stack configuration testing.

### Checking Your Kernel

```bash
# Check current kernel
uname -r

# List installed kernels
rpm -qa kernel | sort -V        # Fedora
dpkg -l | grep linux-image      # Ubuntu

# List boot entries
sudo grubby --info=ALL | grep -E "(title|kernel)"

# Set kernel for next boot
sudo grubby --set-default /boot/vmlinuz-VERSION

# Reboot
sudo reboot
```

## Glossary

| Term | Definition |
|------|------------|
| gfx1151 | AMD GPU architecture identifier for Strix Halo |
| RDNA 3.5 | GPU architecture (between RDNA 3 and RDNA 4) |
| GTT | Graphics Translation Table - dynamic GPU memory |
| GART | Graphics Address Remapping Table - fixed GPU memory |
| rocWMMA | ROCm Wave Matrix Multiply-Accumulate library |
| hipBLASLt | AMD's lightweight BLAS library for HIP |
| AOTriton | AMD's OpenAI Triton fork |
| TheRock | AMD's ROCm nightly build system |
| pp/tg | Prompt processing / token generation (llama.cpp metrics) |
| FA | Flash Attention |
| Toolbox | Fedora's containerized development environment |
| Distrobox | Universal container manager supporting multiple distros |
| VRAM estimator | Tool to calculate GPU memory needs for GGUF models |
| RPC | Remote Procedure Call - enables distributed inference |
| MES | Micro Engine Scheduler (GPU job scheduler) |
| SDMA | System DMA engine (can cause artifacts if enabled) |
| HSA | Heterogeneous System Architecture (AMD's programming model) |

## Version History

- **2026-01-26**: Split KNOWLEDGE_BASE.md into topic-specific documentation
  - Created docs/ directory structure
  - Organized by hardware, ROCm, applications, troubleshooting, community
- **2026-01-24**: Added comprehensive kyuz0 toolboxes documentation
  - Pre-built Vulkan and ROCm containers for llama.cpp
  - Critical runtime flags (--no-mmap, -fa 1) documented
  - VRAM estimator and distributed inference tools
  - Updated kernel parameters with kyuz0's tested configuration
- **2026-01**: Initial comprehensive documentation
  - Based on community work through January 2026
  - Software stack rapidly evolving - verify current status before major decisions

---

**Back to**: [KNOWLEDGE_BASE.md](../KNOWLEDGE_BASE.md)
