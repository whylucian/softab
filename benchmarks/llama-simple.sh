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
CONTAINER_FLAGS="--device=/dev/dri"
if [[ "$IMAGE" == *"hip"* ]] || [[ "$IMAGE" == *"rocm"* ]]; then
    CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host"
    echo "Detected HIP/ROCm backend - using --ipc=host"
fi

podman run --rm \
    $CONTAINER_FLAGS \
    -v "$(dirname $MODEL):/models:ro" \
    "$IMAGE" \
    llama-cli \
        --model "/models/$(basename $MODEL)" \
        --no-mmap \
        -ngl 999 \
        -fa 1 \
        -p "Hello, how are you?" \
        -n 32 \
        --log-disable 2>&1 | tee /tmp/llama-simple-test.log

if [ $? -eq 0 ]; then
    echo ""
    echo "=== SUCCESS: Model loaded and generated tokens ==="
else
    echo ""
    echo "=== FAILED: Check output above for errors ==="
    exit 1
fi
