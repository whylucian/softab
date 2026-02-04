# AMD Strix Halo (gfx1151) AI Software Stack - Knowledge Base

> **Last Updated**: February 2026
> **Primary Sources**: [lhl/strix-halo-testing](https://github.com/lhl/strix-halo-testing), [Strix Halo Wiki](https://strixhalo.wiki/AI/AI_Capabilities_Overview), [llm-tracker.info](https://llm-tracker.info/_TOORG/Strix-Halo)

---

> **Note**: This knowledge base is reference material curated from community sources. The SoftAb project's ablation scope is narrower: we test software stack configurations (drivers, ROCm versions, installation methods, backends) - not model comparisons, quantization sweeps, or inference parameter tuning. See [README.md](README.md) for project scope.

## SoftAb's Approach to Dependency Hell

AMD Strix Halo's software ecosystem is rapidly evolving with frequent breaking changes:
- Kernel updates break ROCm packages
- ROCm version X works with kernel Y but not Z
- Firmware versions can break GPU detection
- Different installation methods (Fedora repos, AMD repos, TheRock nightlies) have different compatibility

**Instead of manually troubleshooting**, SoftAb provides:
- Pre-configured Docker images for every major combination
- Automated test scripts that quickly identify what works
- Structured documentation of failures (error patterns, root causes)

**When you upgrade your kernel**, run an experiment to test all configs. Most will fail - document the failures to build a compatibility matrix for your environment.

---

## Executive Summary

AMD Strix Halo (Ryzen AI Max+ 395) offers **128GB unified memory** enabling 70B+ parameter models on a single chip. The software stack is maturing but requires careful configuration.

**Key Findings**:
- **Vulkan outperforms ROCm 2-2.5x for prompt processing** in most scenarios
- **ROCm + rocWMMA + Flash Attention excels at long context** (8K+)
- **Fedora 43 is recommended** over Ubuntu 24.04 (simpler ROCm install, newer kernel)
- **Kernel 6.15+ required**, 6.16.9+ fixes VRAM visibility bugs
- **⚠️ Current kernel 6.18.6** - Standard ROCm broken, MUST use TheRock nightlies
- Full official ROCm support expected **Q2 2026 with ROCm 7.2.2**
- **~~gfx1100 faster than gfx1151~~** - OUTDATED! Native gfx1151 (TheRock 7.11) is now **2x faster for transformers**
- **Disable hipBLASLt** (`ROCBLAS_USE_HIPBLASLT=0`) for +20% PyTorch performance

## Quick Reference

| Topic | Quick Answer | Details |
|-------|--------------|---------|
| **Best backend?** | Vulkan RADV for general use; ROCm for long context | [ROCm Support](docs/rocm-support.md) |
| **Best distro?** | Fedora 43 | [Applications](docs/applications.md#linux-distribution-recommendations) |
| **Kernel version?** | 6.18.3-200 (avoid 6.18.4+) | [Troubleshooting](docs/troubleshooting.md#kernel-6184-vs-6183-compatibility) |
| **ROCm version?** | TheRock 7.11 (best), 7.2.0 (official), or 6.4.4 (stable fallback) | [ROCm Support](docs/rocm-support.md#official-support-timeline) |
| **Required flags?** | `--no-mmap -ngl 999 -fa 1` for llama.cpp | [Troubleshooting](docs/troubleshooting.md#llamacpp-specific-optimizations) |
| **GPU not detected?** | Check kernel 6.16.9+, firmware not 20251125 | [Troubleshooting](docs/troubleshooting.md#vram-visibility-bug) |
| **Turnkey solution?** | kyuz0 toolboxes for llama.cpp | [Applications](docs/applications.md#kyuz0-strix-halo-toolboxes-recommended) |

## Documentation Structure

### [Hardware Specifications](docs/hardware-specs.md)
- GPU compute specifications (59.4 TFLOPS peak FP16)
- Memory architecture (128GB unified LPDDR5X)
- Comparison with competition (M4 Max, DGX Spark, RTX PRO)
- Model capacity guide (70B comfortable, 235B Q3_K near limit)
- Performance baselines

### [ROCm Support](docs/rocm-support.md)
- Official support timeline (6.4.4 stable, 7.2.2 coming Q2 2026)
- Library support (rocBLAS, hipBLASLt, rocWMMA, AOTriton)
- TheRock nightlies installation
- Critical environment variables (`HSA_ENABLE_SDMA=0`)
- Backend performance comparison (Vulkan vs HIP)
- PyTorch compatibility and installation
- Triton/AOTriton support

### [Applications and Software](docs/applications.md)
- Linux distribution recommendations (Fedora 43 vs Ubuntu 24.04)
- Application support status:
  - llama.cpp (Vulkan ✅, ROCm HIP ✅)
  - Ollama (Vulkan mode supported)
  - vLLM (official support via PR #25908)
  - whisper.cpp (ROCm 7.0.1+ working)
  - pyannote-audio (GPU acceleration working)
- Turnkey solutions:
  - kyuz0 Strix Halo Toolboxes (recommended for llama.cpp)
  - Ryzers (AMD Research framework)
  - Ryzen AI SDK 1.6.1
  - GAIA, Lemonade Server
- Reference Dockerfiles for gfx1151

### [Troubleshooting and Optimization](docs/troubleshooting.md)
- Known issues and workarounds:
  - VRAM visibility bug (upgrade to kernel 6.16.9+)
  - GPU stuck at low clocks (`echo high` fix)
  - MES/kernel hangs (`amdgpu.cwsr_enable=0`)
  - Bad firmware (avoid 20251125)
  - Kernel 6.18.4+ compatibility (use 6.18.3-200)
  - Container permission denied
- Performance optimization:
  - System-level (tuned, IOMMU disable, force high perf)
  - llama.cpp specific (`--no-mmap`, `-fa 1`, `-ngl 999`)
  - Flash Attention impact (+11.5% pp, +8.8% tg)
  - Environment variables reference
  - Vulkan driver selection and batch sizes
- Diagnostic commands

### [Community Resources](docs/community-resources.md)
- Primary documentation (Strix Halo Wiki, lhl's repo, llm-tracker.info)
- Interactive tools (benchmark viewer, forums, Discord)
- Key repositories (kyuz0, scottt, lhl, lemonade-sdk)
- Lemonade Server (AMD official)
- Kernel and container considerations
- Glossary of terms
- Version history

## Hardware Target

- **APU**: AMD Ryzen AI Max+ 395 (Strix Halo)
- **GPU**: Radeon 8060S (40 CU, gfx1151)
- **Architecture**: RDNA 3.5 / Zen 5
- **Memory**: 128GB unified LPDDR5X-8000 (256 GB/s GPU bandwidth)
- **Peak FP16**: 59.4 TFLOPS theoretical

## Essential Commands

```bash
# Required environment variables
export HSA_ENABLE_SDMA=0
export PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"

# llama.cpp critical flags
llama-cli --no-mmap -ngl 999 -fa 1 -m model.gguf

# Check GPU
rocminfo | grep gfx
rocm-smi --showmeminfo vram

# Force high performance
echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
```

## Quick Links

- **Getting Started**: [QUICKSTART.md](QUICKSTART.md)
- **Project Overview**: [README.md](README.md)
- **Experiment Methodology**: [experiments/README.md](experiments/README.md)
- **Quick Reference**: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- **PyTorch Benchmarks**: [docker/pytorch/BENCHMARKS.md](docker/pytorch/BENCHMARKS.md) - Image compatibility, NN throughput, environment variables
- **Whisper Benchmarks**: [docker/whisper-cpp/BENCHMARKS.md](docker/whisper-cpp/BENCHMARKS.md) - Transcription speed, backend comparison, SDMA findings
- **Pyannote Benchmarks**: [docker/pyannote/BENCHMARKS.md](docker/pyannote/BENCHMARKS.md) - Speaker diarization, ROCm 6.2 compatibility
- **Audio Pipeline**: [docker/audio-pipeline/BENCHMARKS.md](docker/audio-pipeline/BENCHMARKS.md) - VAD + Whisper + Pyannote combined pipeline

## Contributing

This knowledge base is community-driven. If you find issues or have updates:
1. Test your findings on Strix Halo hardware
2. Document your system configuration (kernel, ROCm version, etc.)
3. Submit issues or PRs to [SoftAb GitHub](https://github.com/your-repo)
4. Share benchmarks at [llm-tracker.info](https://llm-tracker.info/_TOORG/Strix-Halo)

## License

Knowledge base content is MIT licensed. Community contributions acknowledged.

---

**Last major update**: 2026-02-02 (Added ROCm 7.2 info, PyTorch NN benchmark data, hipBLASLt findings)
**Software stack status**: Rapidly evolving - verify current status before major decisions
