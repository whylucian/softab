#!/bin/bash
# Record non-mutable environment variables for this experiment

echo "=== SoftAb Experiment Environment ==="
echo "Recorded: $(date -Iseconds)"
echo ""

echo "=== Kernel ==="
echo "Version: $(uname -r)"
echo "Kernel Parameters:"
cat /proc/cmdline
echo ""

echo "=== Distribution ==="
cat /etc/os-release
echo ""

echo "=== Hardware ==="
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo ""

echo "=== GPU ==="
if command -v rocminfo &> /dev/null; then
    rocminfo | grep -A 3 "Marketing Name"
    echo ""
    echo "ROCm installed:"
    if [ -f /opt/rocm/.info/version ]; then
        echo "  Version: $(cat /opt/rocm/.info/version)"
    fi
fi

if command -v vulkaninfo &> /dev/null; then
    echo ""
    echo "Vulkan driver:"
    vulkaninfo --summary 2>/dev/null | grep -E "(driverName|driverInfo)" | head -4
fi

echo ""
echo "=== Firmware ==="
rpm -qa | grep linux-firmware || dpkg -l | grep linux-firmware
echo ""

echo "=== Memory Configuration ==="
echo "GART/GTT settings:"
grep -H . /sys/module/amdgpu/parameters/* 2>/dev/null | grep -E "(gtt|gart)" || echo "Not available"
echo ""

echo "=== Container Runtime ==="
podman --version 2>/dev/null || docker --version 2>/dev/null || echo "Not found"
echo ""

echo "=== Peak Theoretical Performance ==="
echo "FP16: 59.4 TFLOPS (AMD Radeon 8060S, 40 CU @ 2.9 GHz)"
echo "Memory Bandwidth: 256 GB/s (GPU), ~128 GB/s (CPU)"
