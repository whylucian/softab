# Strix Halo Software Stack - Quick Reference

## Scope

This project tests **software stack compatibility and performance** on Strix Halo:
- GFX target, driver (AMDVLK/RADV), ROCm version, installation method, backend
- NOT model comparisons, quantization sweeps, or inference tuning

## What Works

| Stack | PyTorch | whisper.cpp | llama.cpp |
|-------|---------|-------------|-----------|
| **TheRock nightlies + gfx1151** | ✅ | ✅ | ✅ |
| **scottt/rocm-TheRock wheels** | ✅ | N/A | N/A |
| **AMD ROCm 6.4.4 + HSA_OVERRIDE** | ⚠️ Unstable | ✅ | ✅ |
| **Fedora ROCm packages** | ❓ | ✅ | ✅ |
| **Official PyTorch wheels (rocm6.2)** | ❌ | N/A | N/A |
| **Vulkan backend** | N/A | N/A | ✅ |

## Required Environment Variables

```bash
# Always needed for stability
export HSA_ENABLE_SDMA=0

# For PyTorch
export PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"

# If using HSA_OVERRIDE workaround (not recommended)
export HSA_OVERRIDE_GFX_VERSION=11.0.0
```

## Kernel Parameters

Add to GRUB_CMDLINE_LINUX_DEFAULT:
```
amd_iommu=off amdgpu.gttsize=131072 amdgpu.cwsr_enable=0
```

## llama.cpp Flags

```bash
--no-mmap -ngl 999    # Required for ROCm backend
```

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| "invalid device function" | Missing gfx1151 kernels | Use TheRock nightlies |
| Only 15.5GB VRAM visible | Kernel bug | Upgrade to 6.16.9+ |
| MES/kernel hangs | CWSR issue | Add `amdgpu.cwsr_enable=0` |
| Checkerboard artifacts | SDMA bug | Set `HSA_ENABLE_SDMA=0` |
| Build fails on kernel 6.18+ | ROCm incompatible | Use TheRock nightlies |

## Installation Paths

### Fedora 43 (Recommended)
```bash
sudo dnf install rocm-hip-devel
```

### TheRock Nightlies (for kernel 6.18+)
```bash
# See docker/rocm/Dockerfile.therock
```

### PyTorch with gfx1151 Support
```bash
# Option 1: scottt wheels (recommended)
pip install "https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl"

# Option 2: AMD nightlies
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ --pre torch
```

## Key Resources

- **Wiki**: strixhalo.wiki
- **Testing repo**: github.com/lhl/strix-halo-testing
- **Containers**: github.com/kyuz0/amd-strix-halo-toolboxes
