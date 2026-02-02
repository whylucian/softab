#!/bin/bash
# Simple PyTorch test - does it work?
# Tests basic GPU access and runs a minimal matmul

set -e

IMAGE="${1}"
if [ -z "$IMAGE" ]; then
    echo "Usage: $0 IMAGE_NAME"
    echo "Example: $0 softab:pytorch-rocm72-gfx1151"
    exit 1
fi

echo "=== PyTorch Simple Test ==="
echo "Image: $IMAGE"
echo "Testing: Basic GPU access and minimal computation"
echo ""

podman run --rm -i \
    --device=/dev/kfd --device=/dev/dri \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --security-opt label=disable \
    "$IMAGE" python3 << 'EOF'
import torch
import sys

print("PyTorch version:", torch.__version__)
print("ROCm available:", torch.cuda.is_available())

if not torch.cuda.is_available():
    print("ERROR: ROCm/CUDA not available")
    sys.exit(1)

print("ROCm version:", torch.version.hip)
print("Device count:", torch.cuda.device_count())
print("Device name:", torch.cuda.get_device_name(0))
print("Device properties:", torch.cuda.get_device_properties(0))

# Simple matmul test
print("\nRunning simple matmul test (512x512 FP32)...")
a = torch.randn(512, 512, device='cuda')
b = torch.randn(512, 512, device='cuda')
c = torch.matmul(a, b)
torch.cuda.synchronize()

print("SUCCESS: Basic GPU compute works")
print("Result shape:", c.shape)
print("Result sample:", c[0, 0].item())
EOF

echo ""
echo "=== Test Complete ==="
