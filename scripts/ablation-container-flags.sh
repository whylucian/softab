#!/bin/bash
# Ablation study: Container runtime flags for ROCm 7.2
# Test which flags are actually required for Strix Halo APU
#
# Usage: ./ablation-container-flags.sh <image> [model_path]
#
# Example: ./ablation-container-flags.sh softab:llama-hip-rocm72-gfx1151 /models/tinyllama.gguf

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results/container-flags"
mkdir -p "$RESULTS_DIR"

IMAGE="${1:-softab:llama-hip-rocm72-gfx1151}"
MODEL="${2:-/models/test.gguf}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if ! command -v podman &> /dev/null; then
    echo "Error: podman not found. This script requires podman."
    exit 1
fi

echo "=== Container Flags Ablation ==="
echo "Image: $IMAGE"
echo "Model: $MODEL"
echo "Results: $RESULTS_DIR"
echo ""

# Test configurations
declare -A CONFIGS=(
    ["baseline"]="--device=/dev/kfd --device=/dev/dri"
    ["ipc-host"]="--device=/dev/kfd --device=/dev/dri --ipc=host"
    ["seccomp"]="--device=/dev/kfd --device=/dev/dri --security-opt seccomp=unconfined"
    ["ipc-seccomp"]="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined"
    ["privileged"]="--device=/dev/kfd --device=/dev/dri --privileged"
    ["all-flags"]="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --cap-add=SYS_PTRACE"
)

RESULTS_FILE="$RESULTS_DIR/flags-ablation-${TIMESTAMP}.json"
echo "{" > "$RESULTS_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$RESULTS_FILE"
echo "  \"image\": \"$IMAGE\"," >> "$RESULTS_FILE"
echo "  \"model\": \"$MODEL\"," >> "$RESULTS_FILE"
echo "  \"tests\": {" >> "$RESULTS_FILE"

first=true
for config_name in "${!CONFIGS[@]}"; do
    flags="${CONFIGS[$config_name]}"

    echo "---"
    echo "Testing: $config_name"
    echo "Flags: $flags"

    if [ "$first" = false ]; then
        echo "," >> "$RESULTS_FILE"
    fi
    first=false

    echo -n "    \"$config_name\": {" >> "$RESULTS_FILE"
    echo -n "\"flags\": \"$flags\", " >> "$RESULTS_FILE"

    # Try to run llama-bench
    set +e
    output=$(podman run --rm $flags \
        -v "$(dirname "$MODEL"):/models:ro" \
        "$IMAGE" \
        llama-bench --mmap 0 -ngl 999 -m "$MODEL" -p 512 -n 32 2>&1)
    exit_code=$?
    set -e

    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "model"; then
        # Extract performance metrics if available
        pp_speed=$(echo "$output" | grep -oP 'pp512.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")
        tg_speed=$(echo "$output" | grep -oP 'tg32.*?\K[0-9.]+(?=\s+±)' | head -1 || echo "0")

        echo "✓ SUCCESS (pp: ${pp_speed} t/s, tg: ${tg_speed} t/s)"

        echo -n "\"status\": \"success\", " >> "$RESULTS_FILE"
        echo -n "\"pp512_ts\": $pp_speed, " >> "$RESULTS_FILE"
        echo -n "\"tg32_ts\": $tg_speed, " >> "$RESULTS_FILE"
        echo -n "\"exit_code\": $exit_code" >> "$RESULTS_FILE"
    else
        # Extract error message
        error_msg=$(echo "$output" | grep -i "error\|critical\|segfault\|abort" | head -1 | sed 's/"/\\"/g')
        echo "✗ FAILED: $error_msg"

        echo -n "\"status\": \"failed\", " >> "$RESULTS_FILE"
        echo -n "\"error\": \"$error_msg\", " >> "$RESULTS_FILE"
        echo -n "\"exit_code\": $exit_code" >> "$RESULTS_FILE"
    fi

    echo "}" >> "$RESULTS_FILE"
    sleep 2  # Cool down between tests
done

echo "" >> "$RESULTS_FILE"
echo "  }" >> "$RESULTS_FILE"
echo "}" >> "$RESULTS_FILE"

echo ""
echo "=== Results Summary ==="
cat "$RESULTS_FILE" | jq -r '.tests | to_entries[] | "\(.key): \(.value.status)"'

echo ""
echo "Full results: $RESULTS_FILE"
echo ""
echo "=== Analysis ==="
echo "Required flags:"
cat "$RESULTS_FILE" | jq -r '.tests | to_entries | map(select(.value.status == "success")) | map(.key) | .[]' | while read -r cfg; do
    echo "  - $cfg"
done

echo ""
echo "Recommended minimal flags:"
# Find the simplest working config (fewest flags)
cat "$RESULTS_FILE" | jq -r '.tests | to_entries | map(select(.value.status == "success")) | sort_by(.value.flags | split(" ") | length) | .[0] | "  " + .value.flags'
