#!/bin/bash
# Qwen3 80B A3B model benchmark sweep
# Tests both Qwen3 80B A3B models on all llama images
# pp2048, tg512

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_DIR}/results"

# Models to test
MODELS=(
    "/data/models/Qwen3-Coder-Next-Q4_K_M.gguf"
    "/data/models/Qwen3-Next-80B-A3B-Instruct-Q4_K_M.gguf"
)

# Benchmark parameters
PP=2048
TG=512

# Container runtime
CONTAINER_CMD="podman"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/qwen3-80b-sweep_${TIMESTAMP}.log"

echo "=== Qwen3 80B A3B Benchmark Sweep ===" | tee "$RESULTS_FILE"
echo "Started: $(date)" | tee -a "$RESULTS_FILE"
echo "Parameters: pp${PP}, tg${TG}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Discover all llama images
mapfile -t IMAGES < <($CONTAINER_CMD images --format '{{.Repository}}:{{.Tag}}' | grep -E '^localhost/softab:llama' | sort)

echo "Found ${#IMAGES[@]} llama images" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Function to get container flags based on image type
get_container_flags() {
    local image="$1"
    if [[ "$image" == *"hip"* ]] || [[ "$image" == *"rocm"* ]] || [[ "$image" == *"therock"* ]] || [[ "$image" == *"rocwmma"* ]] || [[ "$image" == *"gfx"* ]]; then
        echo "--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt=label=disable"
    else
        echo "--device=/dev/dri --security-opt=label=disable"
    fi
}

# Run benchmarks
for MODEL in "${MODELS[@]}"; do
    MODEL_NAME=$(basename "$MODEL" .gguf)
    echo "=============================================" | tee -a "$RESULTS_FILE"
    echo -e "${BLUE}MODEL: $MODEL_NAME${NC}" | tee -a "$RESULTS_FILE"
    echo "=============================================" | tee -a "$RESULTS_FILE"

    for IMAGE in "${IMAGES[@]}"; do
        echo "" | tee -a "$RESULTS_FILE"
        echo "---------------------------------------------" | tee -a "$RESULTS_FILE"
        echo -e "${YELLOW}Image: $IMAGE${NC}" | tee -a "$RESULTS_FILE"
        echo "---------------------------------------------" | tee -a "$RESULTS_FILE"

        FLAGS=$(get_container_flags "$IMAGE")

        echo "Running: llama-bench -p $PP -n $TG -ngl 999 -fa 1 -mmp 0" | tee -a "$RESULTS_FILE"

        if timeout 600 $CONTAINER_CMD run --rm \
            $FLAGS \
            -v "/data/models:/models:ro" \
            "$IMAGE" \
            llama-bench \
                --model "/models/$(basename $MODEL)" \
                -p "$PP" \
                -n "$TG" \
                -ngl 999 \
                -fa 1 \
                -mmp 0 \
                -r 3 \
                -o md 2>&1 | tee -a "$RESULTS_FILE"; then
            echo -e "${GREEN}DONE${NC}: $IMAGE"
        else
            echo -e "${RED}FAILED or TIMEOUT${NC}: $IMAGE" | tee -a "$RESULTS_FILE"
        fi
    done
done

echo "" | tee -a "$RESULTS_FILE"
echo "=== Sweep Complete ===" | tee -a "$RESULTS_FILE"
echo "Finished: $(date)" | tee -a "$RESULTS_FILE"
echo "Results: $RESULTS_FILE"
