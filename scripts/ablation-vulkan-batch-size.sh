#!/bin/bash
# Ablation study: Vulkan batch size (-ub) tuning per driver
# Tests optimal -ub (ubatch) values for RADV vs AMDVLK
#
# Usage: ./ablation-vulkan-batch-size.sh <driver> [model_path]
#
# Example:
#   ./ablation-vulkan-batch-size.sh RADV /models/tinyllama.gguf
#   ./ablation-vulkan-batch-size.sh AMDVLK /models/tinyllama.gguf

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results/vulkan-batch-size"
mkdir -p "$RESULTS_DIR"

DRIVER="${1:-RADV}"
MODEL="${2:-/models/test.gguf}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Images for each driver
IMAGE_RADV="softab:llama-vulkan-radv"
IMAGE_AMDVLK="softab:llama-vulkan-amdvlk"

if [ "$DRIVER" = "RADV" ]; then
    IMAGE="$IMAGE_RADV"
elif [ "$DRIVER" = "AMDVLK" ]; then
    IMAGE="$IMAGE_AMDVLK"
else
    echo "Error: Driver must be RADV or AMDVLK"
    exit 1
fi

if ! command -v podman &> /dev/null; then
    echo "Error: podman not found"
    exit 1
fi

echo "=== Vulkan Batch Size Ablation ==="
echo "Driver: $DRIVER"
echo "Image: $IMAGE"
echo "Model: $MODEL"
echo "Results: $RESULTS_DIR"
echo ""

# Batch size sweep (KNOWLEDGE_BASE suggests AMDVLK=512, RADV=1024)
BATCH_SIZES=(128 256 512 1024 2048 4096)

RESULTS_FILE="$RESULTS_DIR/batch-size-${DRIVER,,}-${TIMESTAMP}.json"

echo "{" > "$RESULTS_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$RESULTS_FILE"
echo "  \"driver\": \"$DRIVER\"," >> "$RESULTS_FILE"
echo "  \"image\": \"$IMAGE\"," >> "$RESULTS_FILE"
echo "  \"model\": \"$MODEL\"," >> "$RESULTS_FILE"
echo "  \"tests\": [" >> "$RESULTS_FILE"

first=true
for ub in "${BATCH_SIZES[@]}"; do
    echo "---"
    echo "Testing: -ub $ub"

    if [ "$first" = false ]; then
        echo "," >> "$RESULTS_FILE"
    fi
    first=false

    # Run benchmark with specific batch size
    set +e
    output=$(podman run --rm \
        --device=/dev/dri \
        -v "$(dirname "$MODEL"):/models:ro" \
        "$IMAGE" \
        llama-bench --mmap 0 -ngl 999 -ub "$ub" -m "$MODEL" \
        -p 512,1024,2048,4096 -n 32 2>&1)
    exit_code=$?
    set -e

    echo "    {" >> "$RESULTS_FILE"
    echo "      \"ubatch\": $ub," >> "$RESULTS_FILE"

    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "model"; then
        # Extract metrics for each context length
        pp512=$(echo "$output" | grep "pp512" | grep -oP 'pp512.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")
        pp1024=$(echo "$output" | grep "pp1024" | grep -oP 'pp1024.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")
        pp2048=$(echo "$output" | grep "pp2048" | grep -oP 'pp2048.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")
        pp4096=$(echo "$output" | grep "pp4096" | grep -oP 'pp4096.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")
        tg32=$(echo "$output" | grep "tg32" | grep -oP 'tg32.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")

        echo "✓ pp512=$pp512 pp1024=$pp1024 pp2048=$pp2048 pp4096=$pp4096 tg32=$tg32"

        echo "      \"status\": \"success\"," >> "$RESULTS_FILE"
        echo "      \"pp512_ts\": $pp512," >> "$RESULTS_FILE"
        echo "      \"pp1024_ts\": $pp1024," >> "$RESULTS_FILE"
        echo "      \"pp2048_ts\": $pp2048," >> "$RESULTS_FILE"
        echo "      \"pp4096_ts\": $pp4096," >> "$RESULTS_FILE"
        echo "      \"tg32_ts\": $tg32" >> "$RESULTS_FILE"
    else
        error_msg=$(echo "$output" | grep -i "error\|failed" | head -1 | sed 's/"/\\"/g')
        echo "✗ FAILED: $error_msg"

        echo "      \"status\": \"failed\"," >> "$RESULTS_FILE"
        echo "      \"error\": \"$error_msg\"" >> "$RESULTS_FILE"
    fi

    echo "    }" >> "$RESULTS_FILE"
    sleep 2
done

echo "" >> "$RESULTS_FILE"
echo "  ]" >> "$RESULTS_FILE"
echo "}" >> "$RESULTS_FILE"

echo ""
echo "=== Results Summary ==="
echo "Batch size performance for $DRIVER:"
cat "$RESULTS_FILE" | jq -r '.tests[] | select(.status == "success") | "  -ub \(.ubatch): pp512=\(.pp512_ts) pp1024=\(.pp1024_ts) pp2048=\(.pp2048_ts) tg32=\(.tg32_ts) t/s"'

echo ""
echo "Optimal batch size (by prompt processing):"
cat "$RESULTS_FILE" | jq -r '[.tests[] | select(.status == "success")] | max_by(.pp512_ts) | "  -ub \(.ubatch) (pp512: \(.pp512_ts) t/s)"'

echo ""
echo "Full results: $RESULTS_FILE"
echo ""
echo "=== Recommendation ==="
if [ "$DRIVER" = "RADV" ]; then
    echo "KNOWLEDGE_BASE suggests -ub 1024 for RADV"
elif [ "$DRIVER" = "AMDVLK" ]; then
    echo "KNOWLEDGE_BASE suggests -ub 512 for AMDVLK"
fi
echo "Compare with actual best: $(cat "$RESULTS_FILE" | jq -r '[.tests[] | select(.status == "success")] | max_by(.pp512_ts) | "-ub \(.ubatch)"')"
