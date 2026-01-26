#!/bin/bash
# llama.cpp benchmark - performance measurement
# Runs prompt processing and token generation benchmarks

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

echo "=== llama.cpp Benchmark ==="
echo "Image: $IMAGE"
echo "Model: $(basename $MODEL)"
echo "Test: pp512, tg128 (prompt processing 512 tokens, generate 128 tokens)"
echo ""

# Determine container flags based on image type
CONTAINER_FLAGS="--device=/dev/dri"
if [[ "$IMAGE" == *"hip"* ]] || [[ "$IMAGE" == *"rocm"* ]]; then
    CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host"
    echo "Detected HIP/ROCm backend - using --ipc=host"
fi

OUTPUT_FILE="llama_bench_$(date +%Y%m%d_%H%M%S).txt"

echo "Running benchmark..."
podman run --rm \
    $CONTAINER_FLAGS \
    -v "$(dirname $MODEL):/models:ro" \
    "$IMAGE" \
    llama-bench \
        --model "/models/$(basename $MODEL)" \
        --mmap 0 \
        -fa 1 \
        -ngl 999 \
        -p 512 \
        -n 128 2>&1 | tee "$OUTPUT_FILE"

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Key metrics:"
grep -E "pp512|tg128" "$OUTPUT_FILE" || echo "Could not parse results"
