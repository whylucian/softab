#!/bin/bash
# PyTorch GEMM benchmark - performance measurement
# Runs matrix multiplication benchmark to measure TFLOPS

set -e

IMAGE="${1}"
MATRIX_SIZE="${2:-4096}"
ITERATIONS="${3:-1000}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 IMAGE_NAME [MATRIX_SIZE] [ITERATIONS]"
    echo "Example: $0 softab:pytorch-rocm72-gfx1151 4096 1000"
    exit 1
fi

echo "=== PyTorch GEMM Benchmark ==="
echo "Image: $IMAGE"
echo "Matrix Size: ${MATRIX_SIZE}x${MATRIX_SIZE}"
echo "Iterations: $ITERATIONS"
echo "Data Type: FP16"
echo ""

OUTPUT_FILE="pytorch_gemm_$(date +%Y%m%d_%H%M%S).json"

podman run --rm \
    --device=/dev/kfd --device=/dev/dri \
    "$IMAGE" python3 << EOF
import torch
import time
import json
import sys

# Configuration
N = $MATRIX_SIZE
ITERATIONS = $ITERATIONS
dtype = torch.float16

print(f"PyTorch version: {torch.__version__}")
print(f"ROCm version: {torch.version.hip}")
print(f"Device: {torch.cuda.get_device_name(0)}")
print("")

if not torch.cuda.is_available():
    print("ERROR: GPU not available")
    sys.exit(1)

# Allocate matrices
print(f"Allocating {N}x{N} matrices (FP16)...")
a = torch.randn(N, N, device='cuda', dtype=dtype)
b = torch.randn(N, N, device='cuda', dtype=dtype)

# Warmup
print("Warming up (10 iterations)...")
for _ in range(10):
    c = torch.matmul(a, b)
torch.cuda.synchronize()

# Benchmark
print(f"Running benchmark ({ITERATIONS} iterations)...")
start = time.time()
for _ in range(ITERATIONS):
    c = torch.matmul(a, b)
torch.cuda.synchronize()
end = time.time()

elapsed = end - start
ops_per_matmul = 2.0 * N * N * N  # multiply-add counts as 2 ops
total_ops = ops_per_matmul * ITERATIONS
tflops = (total_ops / elapsed) / 1e12

print("")
print("=== Results ===")
print(f"Total time: {elapsed:.3f} seconds")
print(f"Time per iteration: {elapsed/ITERATIONS*1000:.3f} ms")
print(f"Performance: {tflops:.2f} TFLOPS")
print(f"Theoretical peak (FP16): 59.4 TFLOPS")
print(f"Utilization: {tflops/59.4*100:.1f}%")

# Output JSON
result = {
    "image": "$IMAGE",
    "timestamp": "$(date -Iseconds)",
    "matrix_size": N,
    "iterations": ITERATIONS,
    "dtype": "fp16",
    "elapsed_seconds": elapsed,
    "tflops": tflops,
    "peak_tflops": 59.4,
    "utilization_percent": tflops/59.4*100,
    "pytorch_version": torch.__version__,
    "rocm_version": torch.version.hip,
    "device_name": torch.cuda.get_device_name(0)
}

print("")
print(json.dumps(result, indent=2))
EOF

echo ""
echo "=== Benchmark Complete ==="
