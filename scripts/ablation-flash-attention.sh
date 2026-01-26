#!/bin/bash
# Flash Attention Ablation for llama.cpp
# Tests FA=0 vs FA=1 performance impact
#
# Usage: ./ablation-flash-attention.sh <model_path> [backend]
#   backend: vulkan-radv (default), hip-rocm72

set -euo pipefail

MODEL_PATH="${1:-}"
BACKEND="${2:-vulkan-radv}"

if [ -z "$MODEL_PATH" ] || [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found"
    echo "Usage: $0 <model_path> [backend]"
    echo "Example: $0 /data/models/llama-2-7b-q4_0.gguf vulkan-radv"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="results/flash-attention"
OUTPUT_FILE="${OUTPUT_DIR}/fa-ablation-${BACKEND}-${TIMESTAMP}.json"

mkdir -p "$OUTPUT_DIR"

echo "=== Flash Attention Ablation Study ==="
echo "Model: $MODEL_PATH"
echo "Backend: $BACKEND"
echo "Output: $OUTPUT_FILE"
echo ""

# Determine container image based on backend
case "$BACKEND" in
    vulkan-radv)
        IMAGE="softab:llama-vulkan-radv"
        CONTAINER_FLAGS="--device=/dev/dri --group-add video"
        ;;
    hip-rocm72)
        IMAGE="softab:llama-hip-rocm72-gfx1151"
        CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host"
        ;;
    *)
        echo "Error: Unknown backend '$BACKEND'"
        echo "Supported: vulkan-radv, hip-rocm72"
        exit 1
        ;;
esac

# Check if image exists
if ! podman image exists "$IMAGE" 2>/dev/null; then
    echo "Error: Image $IMAGE not found"
    echo "Build it first with: podman build -t $IMAGE -f docker/llama-cpp/Dockerfile.$BACKEND ."
    exit 1
fi

MODEL_NAME=$(basename "$MODEL_PATH")
MODEL_DIR=$(dirname "$(realpath "$MODEL_PATH")")

echo "Running llama-bench with FA ablation..."
echo ""

# Run llama-bench with -fa 0,1 flag (tests both in one run)
BENCH_OUTPUT=$(podman run --rm \
    $CONTAINER_FLAGS \
    -v "$MODEL_DIR:/models:ro" \
    "$IMAGE" \
    llama-bench \
        --mmap 0 \
        -ngl 999 \
        -fa 0,1 \
        -m "/models/$MODEL_NAME" \
        -p 512 \
        -n 128 \
    2>&1 || echo "BENCHMARK_FAILED")

if [[ "$BENCH_OUTPUT" == *"BENCHMARK_FAILED"* ]]; then
    echo "Error: Benchmark failed"
    echo "$BENCH_OUTPUT"
    exit 1
fi

echo "$BENCH_OUTPUT"
echo ""

# Parse results
# llama-bench output format:
# | fa |    pp512 | tg128 |
# |  0 | 908.35   | 46.51 |
# |  1 | 1012.79  | 50.59 |

PP512_FA0=$(echo "$BENCH_OUTPUT" | grep -A1 "| fa |" | tail -1 | awk '{print $5}')
TG128_FA0=$(echo "$BENCH_OUTPUT" | grep -A1 "| fa |" | tail -1 | awk '{print $7}')
PP512_FA1=$(echo "$BENCH_OUTPUT" | grep -A2 "| fa |" | tail -1 | awk '{print $5}')
TG128_FA1=$(echo "$BENCH_OUTPUT" | grep -A2 "| fa |" | tail -1 | awk '{print $7}')

# Calculate improvements
PP_IMPROVEMENT=$(echo "scale=2; ($PP512_FA1 / $PP512_FA0 - 1) * 100" | bc)
TG_IMPROVEMENT=$(echo "scale=2; ($TG128_FA1 / $TG128_FA0 - 1) * 100" | bc)

# Generate JSON output
cat > "$OUTPUT_FILE" << EOFJSON
{
  "run_id": "fa_ablation_${TIMESTAMP}",
  "timestamp": "$(date -Iseconds)",
  "model": "$MODEL_NAME",
  "backend": "$BACKEND",
  "image": "$IMAGE",
  "test_config": {
    "mmap": false,
    "ngl": 999,
    "prompt_tokens": 512,
    "generation_tokens": 128
  },
  "results": {
    "flash_attention_disabled": {
      "pp512_ts": $PP512_FA0,
      "tg128_ts": $TG128_FA0
    },
    "flash_attention_enabled": {
      "pp512_ts": $PP512_FA1,
      "tg128_ts": $TG128_FA1
    },
    "improvement": {
      "pp512_percent": $PP_IMPROVEMENT,
      "tg128_percent": $TG_IMPROVEMENT,
      "pp512_absolute_ts": $(echo "$PP512_FA1 - $PP512_FA0" | bc),
      "tg128_absolute_ts": $(echo "$TG128_FA1 - $TG128_FA0" | bc)
    }
  },
  "raw_output": $(echo "$BENCH_OUTPUT" | jq -Rs .)
}
EOFJSON

echo "=== Results Summary ==="
echo "Prompt Processing (512 tokens):"
echo "  FA=0: $PP512_FA0 t/s"
echo "  FA=1: $PP512_FA1 t/s"
echo "  Improvement: +${PP_IMPROVEMENT}%"
echo ""
echo "Token Generation (128 tokens):"
echo "  FA=0: $TG128_FA0 t/s"
echo "  FA=1: $TG128_FA1 t/s"
echo "  Improvement: +${TG_IMPROVEMENT}%"
echo ""
echo "Results saved to: $OUTPUT_FILE"
