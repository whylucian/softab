#!/bin/bash
# Master benchmark runner for a single experiment
# Runs all workload tests across specified images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname $(dirname "$SCRIPT_DIR"))"
BENCHMARKS_DIR="$PROJECT_ROOT/benchmarks"
RESULTS_DIR="$SCRIPT_DIR/raw_results"

mkdir -p "$RESULTS_DIR"

echo "=== SoftAb Experiment Runner ==="
echo "Experiment: $(basename $SCRIPT_DIR)"
echo "Date: $(date -Iseconds)"
echo ""

# List of images to test - EDIT THIS for your experiment
IMAGES=(
    # Example images - uncomment and edit as needed
    # "softab:pytorch-rocm72-gfx1151"
    # "softab:llama-vulkan-radv"
    # "softab:llama-hip-rocm72"
    # "softab:whisper-hip-rocm72"
)

# Models to test - EDIT THIS for your experiment
LLAMA_MODEL="${LLAMA_MODEL:-/data/models/tinyllama-1.1b-q4.gguf}"
WHISPER_AUDIO="${WHISPER_AUDIO:-/data/audio/test-audio.wav}"

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "ERROR: No images specified in IMAGES array"
    echo "Edit this script and add images to test"
    exit 1
fi

echo "Images to test: ${#IMAGES[@]}"
for img in "${IMAGES[@]}"; do
    echo "  - $img"
done
echo ""

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
        "$BENCHMARKS_DIR/pytorch-simple.sh" "$IMAGE" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_pytorch_simple.log"

        if [ $? -eq 0 ]; then
            echo ""
            echo ">>> PyTorch GEMM Benchmark <<<"
            "$BENCHMARKS_DIR/pytorch-gemm.sh" "$IMAGE" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_pytorch_gemm.log"
        fi

    elif [[ "$IMAGE" == *"llama"* ]]; then
        if [ ! -f "$LLAMA_MODEL" ]; then
            echo "WARNING: LLAMA_MODEL not found: $LLAMA_MODEL"
            echo "Skipping llama.cpp tests"
            continue
        fi

        echo ">>> llama.cpp Simple Test <<<"
        "$BENCHMARKS_DIR/llama-simple.sh" "$IMAGE" "$LLAMA_MODEL" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_llama_simple.log"

        if [ $? -eq 0 ]; then
            echo ""
            echo ">>> llama.cpp Benchmark <<<"
            "$BENCHMARKS_DIR/llama-bench.sh" "$IMAGE" "$LLAMA_MODEL" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_llama_bench.log"
        fi

    elif [[ "$IMAGE" == *"whisper"* ]]; then
        if [ ! -f "$WHISPER_AUDIO" ]; then
            echo "WARNING: WHISPER_AUDIO not found: $WHISPER_AUDIO"
            echo "Skipping whisper.cpp tests"
            continue
        fi

        echo ">>> whisper.cpp Simple Test <<<"
        "$BENCHMARKS_DIR/whisper-simple.sh" "$IMAGE" "$WHISPER_AUDIO" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_whisper_simple.log"

        if [ $? -eq 0 ]; then
            echo ""
            echo ">>> whisper.cpp Benchmark <<<"
            "$BENCHMARKS_DIR/whisper-bench.sh" "$IMAGE" "$WHISPER_AUDIO" 2>&1 | tee "$RESULTS_DIR/${IMAGE_SAFE}_whisper_bench.log"
        fi

    else
        echo "WARNING: Cannot determine workload type for image: $IMAGE"
        echo "Skipping..."
    fi

    echo ""
done

echo ""
echo "=========================================="
echo "Experiment Complete"
echo "=========================================="
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Next steps:"
echo "  1. Review raw_results/*.log files"
echo "  2. Use Claude/LLM to analyze and summarize findings"
echo "  3. Document key findings in FINDINGS.md"
