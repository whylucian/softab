# Experiment Kernel Configuration

Captured: 2026-02-02T20:36:55-05:00

This documents the exact kernel, modules, and boot parameters used for all benchmark experiments.

## Kernel Version

```
6.18.5-200.fc43.x86_64
```

## Kernel Boot Parameters

```
BOOT_IMAGE=(hd1,gpt5)/vmlinuz-6.18.5-200.fc43.x86_64
root=UUID=aece94c3-e6dd-411d-8492-bfa21947e57f
ro
rootflags=subvol=root
rhgb
quiet
amd_iommu=off
amdgpu.vm_size=16384
ttm.pages_limit=33554432
ttm.page_pool_size=33554432
amdgpu.dcdebugmask=0x10
```

### Key Performance Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `amd_iommu` | off | Disable IOMMU translation (see note below) |
| `amdgpu.vm_size` | 16384 | GPU virtual memory size (MB) |
| `ttm.pages_limit` | 33554432 | ~128GB in 4KB pages |
| `ttm.page_pool_size` | 33554432 | TTM page pool size |
| `amdgpu.dcdebugmask` | 0x10 | Display core debug mask |

## Loaded GPU Modules

```
Module                  Size   Used by
amdgpu              20692992   50
amdxcp                 12288   1 amdgpu
cec                   106496   2 drm_display_helper,amdgpu
drm_buddy              32768   1 amdgpu
drm_display_helper    331776   1 amdgpu
drm_exec               12288   1 amdgpu
drm_panel_backlight_quirks    12288   1 amdgpu
drm_suballoc_helper    20480   1 amdgpu
drm_ttm_helper         16384   2 amdgpu
gpu_sched              69632   2 amdxdna,amdgpu
i2c_algo_bit           20480   1 amdgpu
ttm                   135168   2 amdgpu,drm_ttm_helper
video                  81920   1 amdgpu
```

## Module Path

```
/lib/modules/6.18.5-200.fc43.x86_64/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.xz
```

## Performance Impact Uncertainty

There's a reported ~6% performance difference between VRAM-only and unified memory configurations, but the exact source is unknown:

- **Possibility 1**: `amd_iommu=off` removes DMA translation overhead
- **Possibility 2**: Forcing VRAM allocation (coarse-grained memory) avoids fine-grained memory path
- **Possibility 3**: Both are the same underlying mechanism

These may be the same effect observed from different angles. We haven't done proper ablation testing (would require kernel reboots) to isolate the cause.

**Current tradeoff**: We accept any potential performance hit in exchange for ~121GB unified memory, which allows running larger models.

## Notes

- Kernel 6.18.5 is Fedora 43 stock kernel
- IOMMU disabled (unknown if this affects performance independently)
- TTM configured for maximum GPU memory allocation (~128GB)
- Using in-kernel amdgpu driver (not out-of-tree ROCm version)
- Previous benchmark results did not record kernel params, so we cannot correlate configs with performance
