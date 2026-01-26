# Troubleshooting and Optimization

> **Common issues and performance tuning for AMD Strix Halo**

## Known Issues & Workarounds

### VRAM Visibility Bug

**Symptom**: ROCm only sees ~15.5GB instead of allocated VRAM

**Solution**: Upgrade to kernel 6.16.9+

```bash
# Check current kernel
uname -r

# Verify VRAM visibility
rocm-smi --showmeminfo vram
```

### GPU Stuck at Low Clocks

**Symptom**: GPU locked at 885MHz (max should be 2900MHz)

**Workaround**:
```bash
# Check current clock speed
cat /sys/class/drm/card0/device/pp_dpm_sclk

# Force high performance mode
echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Verify it worked
cat /sys/class/drm/card0/device/pp_dpm_sclk
# Should show asterisk (*) next to highest frequency
```

### MES/Kernel Hangs

**Symptom**: System freezes during compute workloads

**Solution**: Add kernel parameter `amdgpu.cwsr_enable=0`

```bash
# Edit /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="... amdgpu.cwsr_enable=0"

# Update GRUB
sudo grub2-mkconfig -o /boot/grub2/grub.cfg  # Fedora
sudo update-grub                              # Ubuntu

# Reboot
sudo reboot
```

### HSA_OVERRIDE_GFX_VERSION Hack

⚠️ **NOT RECOMMENDED for production**

```bash
# Forces gfx1100 kernels (2-6x faster but unstable)
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export HSA_ENABLE_SDMA=0
```

**Issues with HSA_OVERRIDE**:
- Causes eventual MES/kernel errors
- May crash on long-running workloads
- hipBLASLt disabled (reduced performance)
- Not suitable for production use

**Better alternative**: Wait for native gfx1151 support or use TheRock nightlies

### Bad Firmware

**⚠️ AVOID**: `linux-firmware-20251125` - breaks ROCm on Strix Halo (AMD recalled this update)

```bash
# Check installed firmware version
rpm -q linux-firmware

# If 20251125 is installed, downgrade immediately
sudo dnf downgrade linux-firmware

# Lock at good version (20251111)
sudo dnf install 'dnf-command(versionlock)'
sudo dnf versionlock linux-firmware
```

### Kernel 6.18.4+ vs 6.18.3 Compatibility

**⚠️ CRITICAL**: Kernel 6.18.4+ breaks all versions of ROCm **except** cutting-edge nightly builds from TheRock.

**Recommendation** (from kyuz0 testing):
- ✅ **Use 6.18.3-200**: Stable with all ROCm versions (6.4.4, 7.1.1, 7.2)
- ⚠️ **Avoid 6.18.4+**: Breaks standard ROCm packages
- 🔧 **Workaround for 6.18.4+**: Only use ROCm nightly builds (less stable)

**Check and downgrade if needed**:
```bash
# Check current kernel
uname -r

# If on 6.18.4+, list available kernels
rpm -qa kernel | sort -V

# Set 6.18.3 as default
sudo grubby --set-default /boot/vmlinuz-6.18.3-200.fc43.x86_64

# Reboot
sudo reboot
```

**kyuz0's stable configuration**:
```
- Kernel: 6.18.3-200
- Firmware: 20251111
- ROCm: 6.4.4 or 7.1.1 GA
```

### Container Permission Denied

**Symptom**: "Permission denied" when accessing GPU in container

**Solution**: Add correct device flags and security options

```bash
# For ROCm workloads
podman run --device=/dev/kfd --device=/dev/dri \
  --ipc=host \
  --security-opt label=disable \
  IMAGE_NAME

# For Vulkan workloads
podman run --device=/dev/dri \
  --group-add video \
  --security-opt seccomp=unconfined \
  IMAGE_NAME
```

**Explanation**:
- `--device=/dev/kfd` - ROCm compute device
- `--device=/dev/dri` - GPU rendering device
- `--ipc=host` - Required for ROCm on Strix Halo (unified memory)
- `--security-opt label=disable` - Disable SELinux confinement

### Memory Critical Error by Agent Node-0

**Symptom**: "Memory critical error by agent node-0" when running ROCm workloads

**Cause**: Missing `--ipc=host` flag for ROCm containers on unified memory APUs

**Solution**:
```bash
podman run --device=/dev/kfd --device=/dev/dri \
  --ipc=host \  # <-- THIS IS REQUIRED
  IMAGE_NAME
```

## Performance Optimization

### System-Level Optimizations

```bash
# 1. Install tuned and set accelerator profile (5-8% throughput gain)
sudo dnf install tuned
sudo systemctl enable --now tuned
sudo tuned-adm profile accelerator-performance

# 2. Disable IOMMU for ~6% faster memory reads
# Add to /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT="... amd_iommu=off"
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot

# 3. Force high performance mode
echo high | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# 4. Set compute-optimized power profile (for sustained workloads)
rocm-smi --setprofile 4

# 5. Enable Re-Size BAR in BIOS (critical for P2P if multi-GPU)
# Check: lspci -vv | grep -i "Resizable BAR"
```

### llama.cpp Specific Optimizations

**Critical Flags** (Required on Strix Halo):
```bash
--no-mmap     # Mandatory! mmap causes catastrophic slowdown/crashes on ROCm
-ngl 999      # All layers to GPU
-fa 1         # Flash Attention (required for stability)

# Example: Minimum recommended command
llama-cli --no-mmap -ngl 999 -fa 1 -m model.gguf
```

**⚠️ WARNING**: Running without `--no-mmap` and `-fa 1` on Strix Halo can cause:
- Severe performance degradation (10-100x slower)
- Kernel crashes and GPU hangs
- Memory access violations

**For large models using unified memory**:
```bash
# ROCm backend
GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON llama-server ...

# Vulkan backend
GGML_VK_PREFER_HOST_MEMORY=ON llama-server ...
```

### Flash Attention Performance Impact

Based on community testing (llama.cpp/discussions/15021):

| Model | Metric | FA=0 | FA=1 | Improvement |
|-------|--------|------|------|-------------|
| Llama 2 7B Q4_0 | pp512 | 908.35 t/s | 1012.79 t/s | **+11.5%** |
| Llama 2 7B Q4_0 | tg128 | 46.51 t/s | 50.59 t/s | **+8.8%** |

**Configuration**: Debian 6.17.8-1 kernel, llama.cpp v7166

**Key Finding**: Flash Attention provides ~11% improvement for prompt processing and ~9% for token generation on mid-sized models.

### Benchmark Commands

```bash
# Standard benchmark
llama-bench --mmap 0 -fa 1 -ngl 999 -m model.gguf

# Flash Attention ablation (test FA impact)
llama-bench --mmap 0 -fa 0,1 -ngl 999 -m model.gguf

# Long context sweep
llama-bench --mmap 0 -fa 1 -ngl 999 -m model.gguf \
  -p 512,1024,2048,4096 -n 32 -d 0,2000,4000,8000
```

### Environment Variables Reference

**Required for Stability**:
```bash
export HSA_ENABLE_SDMA=0                    # Fix checkerboard artifacts
```

**PyTorch Optimizations**:
```bash
export PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export PYTORCH_ROCM_ARCH="gfx1151"
```

**ROCm Library Optimizations**:
```bash
export ROCBLAS_USE_HIPBLASLT=1              # Better GEMM performance
export ROCM_USE_GTT_FOR_KERNARG=1           # Better memory allocation
```

**Debugging**:
```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0      # Force gfx1100 kernels (not recommended)
export AMD_LOG_LEVEL=3                      # Verbose ROCm logging
export ROCBLAS_VERBOSE=1                    # rocBLAS debug output
```

### Vulkan Driver Selection

```bash
# Use RADV (better stability, better tg performance)
AMD_VULKAN_ICD=RADV llama-cli ...

# Use AMDVLK (better pp performance, but 2GB allocation limit)
AMD_VULKAN_ICD=AMDVLK llama-cli ...

# Or set default system-wide
# Edit /etc/environment:
AMD_VULKAN_ICD=RADV
```

### Optimal Vulkan Batch Sizes

| Driver | Optimal `-ub` | Use Case |
|--------|---------------|----------|
| AMDVLK | 512 | Prompt processing |
| RADV | 1024 | Token generation, stability |

```bash
# Test batch size impact
llama-bench --mmap 0 -fa 1 -ngl 999 \
  -ub 256,512,1024,2048 \
  -m model.gguf
```

## Diagnostic Commands

```bash
# Check GPU detection
rocminfo | grep -E "Name|gfx"
lspci | grep -E "VGA|Display"

# Check VRAM allocation
rocm-smi --showmeminfo vram

# Check GPU clocks
cat /sys/class/drm/card0/device/pp_dpm_sclk
cat /sys/class/drm/card0/device/pp_dpm_mclk

# Check kernel parameters
cat /proc/cmdline

# Check firmware version
rpm -q linux-firmware        # Fedora
dpkg -l | grep linux-firmware # Ubuntu

# Test GPU compute
rocminfo | grep -A 10 "Agent"
/opt/rocm/bin/rocm-smi

# Monitor GPU usage during workload
watch -n 1 rocm-smi
```

---

**Back to**: [KNOWLEDGE_BASE.md](../KNOWLEDGE_BASE.md)
