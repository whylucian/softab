#!/bin/bash
# Simple llama.cpp test - does it work?
# Tests if model loads and generates tokens

set -e

IMAGE="${1}"
MODEL="${2}"

if [ -z "$IMAGE" ] || [ -z "$MODEL" ]; then
    echo "Usage: $0 IMAGE_NAME MODEL_PATH"
    echo "Example: $0 softab:llama-vulkan-radv /data/models/tinyllama-1.1b-q4_k_m.gguf"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "ERROR: Model file not found: $MODEL"
    exit 1
fi

echo "=== llama.cpp Simple Test ==="
echo "Image: $IMAGE"
echo "Model: $(basename $MODEL)"
echo ""

# Determine container flags based on image type
# Security opts needed for ROCm memory operations
CONTAINER_FLAGS="--device=/dev/dri --security-opt seccomp=unconfined --security-opt label=disable"
if [[ "$IMAGE" == *"hip"* ]] || [[ "$IMAGE" == *"rocm"* ]]; then
    CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"
    echo "Detected HIP/ROCm backend - using --ipc=host"
fi

# Use llama-bench for reliable benchmarking (no conversation mode issues)
# HSA env vars help ensure VRAM allocation instead of GTT
podman run --rm \
    $CONTAINER_FLAGS \
    -e HSA_ENABLE_SDMA=0 \
    -e GPU_MAX_HEAP_SIZE=100 \
    -v "$(dirname $MODEL):/models:ro" \
    "$IMAGE" \
    llama-bench \
        --model "/models/$(basename $MODEL)" \
        -ngl 999 \
        -p 512 -n 128 2>&1 | tee /tmp/llama-simple-test.log

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== SUCCESS: Model loaded and generated tokens ==="
else
    echo ""
    echo "=== FAILED: Check output above for errors ==="
    exit 1
fi
