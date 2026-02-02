#!/bin/bash
# Master benchmark runner for all experiments
# Runs all workload tests across all available images

# Don't exit on errors - we want to continue testing all images
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname $(dirname "$SCRIPT_DIR"))"
BENCHMARKS_DIR="$PROJECT_ROOT/benchmarks"
RESULTS_DIR="$SCRIPT_DIR/raw_results"

mkdir -p "$RESULTS_DIR"

echo "=== SoftAb Full Experiment Runner ==="
echo "Experiment: $(basename $SCRIPT_DIR)"
echo "Date: $(date -Iseconds)"
echo ""

# All available images to test
IMAGES=(
    # PyTorch images
    "softab:pytorch-rocm644-official"
    "softab:pytorch-rocm72-official"
    "softab:pytorch-ablation-hsa-xnack-1-gfx1151"
    "softab:pytorch-ablation-hsa-fine-grain-0-gfx1151"
    "softab:pytorch-ablation-hsa-xnack-0-gfx1151"
    "softab:pytorch-ablation-alloc-conf-expandable-gfx1151"

    # llama.cpp images
    "softab:llama-hip-rocm72-vram"
    "softab:llama-vulkan-radv-fa-finegrain"
    "softab:llama-vulkan-radv-fa"
    "softab:llama-hip-rocm644-gfx1151"
    "softab:llama-hip-rocm72-fa0-gfx1151"

    # whisper.cpp images
    "softab:whisper-ablation-sdma-1"
    "softab:whisper-ablation-sdma-0"
    "softab:whisper-vulkan-amdvlk"
    "softab:whisper-hip-rocm72-nofa-gfx1151"
    "softab:whisper-hip-rocm72-mmap-gfx1151"
    "softab:whisper-hip-rocm711-gfx1151"
    "softab:whisper-hip-rocm644-gfx1151"
    "softab:whisper-vulkan-radv"
)

# Models to test
LLAMA_MODEL="${LLAMA_MODEL:-/data/models/tinyllama-1.1b-q4.gguf}"
WHISPER_AUDIO="${WHISPER_AUDIO:-/data/models/test-audio.wav}"

echo "Images to test: ${#IMAGES[@]}"
for img in "${IMAGES[@]}"; do
    echo "  - $img"
done
echo ""
echo "Llama model: $LLAMA_MODEL"
echo "Whisper audio: $WHISPER_AUDIO"
echo ""

# Track results
PASSED=0
FAILED=0
SKIPPED=0

# Run benchmarks for each image
for IMAGE in "${IMAGES[@]}"; do
    echo ""
    echo "=========================================="
    echo "Testing: $IMAGE"
    echo "=========================================="
    echo ""

    IMAGE_SAFE=$(echo "$IMAGE" | tr ':/' '__')

    # Determine workload type from image name
    if [[ "$IMAGE" == *"pytorch"* ]]; then
        echo ">>> PyTorch Simple Test <<<"
        if "$BENCHMARKS_DIR/pytorch-simple.sh" "$IMAGE" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_pytorch_simple.log"; then
            ((PASSED++))
            echo ""
            echo ">>> PyTorch GEMM Benchmark <<<"
            "$BENCHMARKS_DIR/pytorch-gemm.sh" "$IMAGE" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_pytorch_gemm.log" || true
        else
            ((FAILED++))
            echo "FAILED: $IMAGE" >> "$RESULTS_DIR/FAILURES.txt"
        fi

    elif [[ "$IMAGE" == *"llama"* ]]; then
        if [ ! -f "$LLAMA_MODEL" ]; then
            echo "WARNING: LLAMA_MODEL not found: $LLAMA_MODEL"
            echo "Skipping llama.cpp tests"
            ((SKIPPED++))
            continue
        fi

        echo ">>> llama.cpp Simple Test <<<"
        if "$BENCHMARKS_DIR/llama-simple.sh" "$IMAGE" "$LLAMA_MODEL" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_llama_simple.log"; then
            ((PASSED++))
            echo ""
            echo ">>> llama.cpp Benchmark <<<"
            "$BENCHMARKS_DIR/llama-bench.sh" "$IMAGE" "$LLAMA_MODEL" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_llama_bench.log" || true
        else
            ((FAILED++))
            echo "FAILED: $IMAGE" >> "$RESULTS_DIR/FAILURES.txt"
        fi

    elif [[ "$IMAGE" == *"whisper"* ]]; then
        if [ ! -f "$WHISPER_AUDIO" ]; then
            echo "WARNING: WHISPER_AUDIO not found: $WHISPER_AUDIO"
            echo "Skipping whisper.cpp tests"
            ((SKIPPED++))
            continue
        fi

        echo ">>> whisper.cpp Simple Test <<<"
        if "$BENCHMARKS_DIR/whisper-simple.sh" "$IMAGE" "$WHISPER_AUDIO" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_whisper_simple.log"; then
            ((PASSED++))
            echo ""
            echo ">>> whisper.cpp Benchmark <<<"
            "$BENCHMARKS_DIR/whisper-bench.sh" "$IMAGE" "$WHISPER_AUDIO" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_whisper_bench.log" || true
        else
            ((FAILED++))
            echo "FAILED: $IMAGE" >> "$RESULTS_DIR/FAILURES.txt"
        fi

    else
        echo "WARNING: Cannot determine workload type for image: $IMAGE"
        echo "Skipping..."
        ((SKIPPED++))
    fi

    echo ""
done

echo ""
echo "=========================================="
echo "Experiment Complete"
echo "=========================================="
echo ""
echo "Results: PASSED=$PASSED FAILED=$FAILED SKIPPED=$SKIPPED"
echo "Results saved to: $RESULTS_DIR"
echo ""
if [ -f "$RESULTS_DIR/FAILURES.txt" ]; then
    echo "Failed images:"
    cat "$RESULTS_DIR/FAILURES.txt"
fi
