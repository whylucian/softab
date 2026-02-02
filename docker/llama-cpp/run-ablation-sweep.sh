#!/bin/bash
# Ablation sweep script for llama.cpp Dockerfiles
# Builds and runs all ablation variants against a test model
#
# Usage: ./run-ablation-sweep.sh /path/to/model.gguf [output_dir]

set -e

MODEL_PATH="${1:?Usage: $0 /path/to/model.gguf [output_dir]}"
OUTPUT_DIR="${2:-./ablation-results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Verify model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model not found: $MODEL_PATH"
    exit 1
fi

MODEL_DIR=$(dirname "$MODEL_PATH")
MODEL_NAME=$(basename "$MODEL_PATH" .gguf)

mkdir -p "$OUTPUT_DIR"

echo "=== llama.cpp Ablation Sweep ==="
echo "Model: $MODEL_PATH"
echo "Output: $OUTPUT_DIR"
echo "Timestamp: $TIMESTAMP"
echo ""

# Ablation Dockerfiles to test
ABLATIONS=(
    # hipBLASLt comparison
    "Dockerfile.ablation-hipblaslt-0:hipblaslt-disabled"
    "Dockerfile.ablation-hipblaslt-1:hipblaslt-enabled"

    # Vulkan batch size comparison
    "Dockerfile.vulkan-radv-ub1024:vulkan-radv-ub1024"
    "Dockerfile.vulkan-amdvlk-ub512:vulkan-amdvlk-ub512"
    "Dockerfile.vulkan-radv:vulkan-radv-default"
    "Dockerfile.vulkan-amdvlk:vulkan-amdvlk-default"

    # gfx1100 override (risky - optional)
    # "Dockerfile.hip-gfx1100-override:gfx1100-override"

    # TheRock variants
    "Dockerfile.therock-tarball:therock-tarball"
    "Dockerfile.therock:therock-pip"

    # MoE optimized
    "Dockerfile.moe-optimized:moe-optimized"
)

# Results file
RESULTS_FILE="$OUTPUT_DIR/ablation_${MODEL_NAME}_${TIMESTAMP}.csv"
echo "dockerfile,tag,backend,pp512_ts,tg128_ts,status" > "$RESULTS_FILE"

echo "Building and running ${#ABLATIONS[@]} ablation configurations..."
echo ""

for ABLATION in "${ABLATIONS[@]}"; do
    DOCKERFILE="${ABLATION%%:*}"
    TAG="${ABLATION##*:}"
    IMAGE="softab:llama-$TAG"

    echo "=============================================="
    echo "Testing: $TAG"
    echo "Dockerfile: $DOCKERFILE"
    echo "=============================================="

    # Check if Dockerfile exists
    if [ ! -f "$DOCKERFILE" ]; then
        echo "SKIP: Dockerfile not found"
        echo "$DOCKERFILE,$TAG,unknown,0,0,skip-not-found" >> "$RESULTS_FILE"
        continue
    fi

    # Build
    echo "Building $IMAGE..."
    if ! podman build -t "$IMAGE" -f "$DOCKERFILE" . 2>&1 | tail -5; then
        echo "BUILD FAILED"
        echo "$DOCKERFILE,$TAG,unknown,0,0,build-failed" >> "$RESULTS_FILE"
        continue
    fi

    # Run benchmark
    echo "Running benchmark..."
    BENCH_OUTPUT=$(podman run --rm \
        --device /dev/kfd \
        --device /dev/dri \
        --group-add video \
        --group-add render \
        -v "$MODEL_DIR:/models:ro" \
        -e MODEL="/models/$(basename $MODEL_PATH)" \
        "$IMAGE" 2>&1) || {
        echo "RUN FAILED"
        echo "$DOCKERFILE,$TAG,unknown,0,0,run-failed" >> "$RESULTS_FILE"
        continue
    }

    # Parse results (llama-bench output)
    # Look for pp512 and tg128 rows
    PP_TS=$(echo "$BENCH_OUTPUT" | grep -E "pp512|pp 512" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
    TG_TS=$(echo "$BENCH_OUTPUT" | grep -E "tg128|tg 128" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")

    # Determine backend from Dockerfile name
    BACKEND="unknown"
    [[ "$DOCKERFILE" == *"vulkan"* ]] && BACKEND="vulkan"
    [[ "$DOCKERFILE" == *"hip"* ]] && BACKEND="hip"
    [[ "$DOCKERFILE" == *"therock"* ]] && BACKEND="therock"
    [[ "$DOCKERFILE" == *"moe"* ]] && BACKEND="vulkan-moe"

    echo "Results: pp512=${PP_TS:-N/A} t/s, tg128=${TG_TS:-N/A} t/s"
    echo "$DOCKERFILE,$TAG,$BACKEND,${PP_TS:-0},${TG_TS:-0},success" >> "$RESULTS_FILE"

    # Save full output
    echo "$BENCH_OUTPUT" > "$OUTPUT_DIR/${TAG}_${TIMESTAMP}.log"

    echo ""
done

echo "=============================================="
echo "Ablation sweep complete!"
echo "Results: $RESULTS_FILE"
echo ""
echo "Summary:"
cat "$RESULTS_FILE" | column -t -s,
