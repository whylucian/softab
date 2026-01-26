#!/bin/bash
# Run llama-simple test on all llama.cpp images
# Discovers built images automatically and tests each one

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_DIR}/results"

# Default model path (override with first argument)
MODEL="${1:-}"

# Container runtime
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
else
    echo "Error: Neither podman nor docker found" >&2
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 MODEL_PATH

Run llama-simple test on all built llama.cpp images.

Arguments:
    MODEL_PATH    Path to a GGUF model file

Example:
    $0 /data/models/tinyllama-1.1b-q4_k_m.gguf

Output:
    Results are saved to: results/llama-simple-all_TIMESTAMP.log
    Summary shows PASS/FAIL for each image
EOF
    exit 1
}

if [ -z "$MODEL" ]; then
    usage
fi

if [ ! -f "$MODEL" ]; then
    echo -e "${RED}ERROR: Model file not found: $MODEL${NC}"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/llama-simple-all_${TIMESTAMP}.log"
SUMMARY_FILE="${RESULTS_DIR}/llama-simple-summary_${TIMESTAMP}.txt"

echo "=== Llama Simple Test - All Images ===" | tee "$RESULTS_FILE"
echo "Started: $(date)" | tee -a "$RESULTS_FILE"
echo "Model: $MODEL" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Find all llama images and store in array
echo -e "${BLUE}Discovering llama images...${NC}"
mapfile -t IMAGES < <($CONTAINER_CMD images --format '{{.Repository}}:{{.Tag}}' | grep -E '(softab|localhost/softab):llama' | sort)

IMAGE_COUNT=${#IMAGES[@]}

if [ "$IMAGE_COUNT" -eq 0 ]; then
    echo -e "${RED}No llama images found!${NC}"
    echo "Build images first with: cd docker && ./build-matrix.sh build-llama"
    exit 1
fi

echo -e "${BLUE}Found $IMAGE_COUNT llama images${NC}"
echo "" | tee -a "$RESULTS_FILE"

# Track results
PASSED=0
FAILED=0
PASS_LIST=()
FAIL_LIST=()

# Run test on each image
CURRENT=0
for IMAGE in "${IMAGES[@]}"; do
    ((CURRENT++))
    echo "=============================================" | tee -a "$RESULTS_FILE"
    echo -e "${BLUE}[$CURRENT/$IMAGE_COUNT] Testing: $IMAGE${NC}" | tee -a "$RESULTS_FILE"
    echo "=============================================" | tee -a "$RESULTS_FILE"

    # Run the simple test
    if "$PROJECT_DIR/benchmarks/llama-simple.sh" "$IMAGE" "$MODEL" >> "$RESULTS_FILE" 2>&1; then
        echo -e "${GREEN}PASS${NC}: $IMAGE"
        ((PASSED++))
        PASS_LIST+=("$IMAGE")
    else
        echo -e "${RED}FAIL${NC}: $IMAGE"
        ((FAILED++))
        FAIL_LIST+=("$IMAGE")
    fi
    echo "" | tee -a "$RESULTS_FILE"
done

# Print summary
echo ""
echo "============================================="
echo "                  SUMMARY"
echo "============================================="
echo "Completed: $(date)"
echo "Model: $(basename "$MODEL")"
echo ""
echo -e "Total: $IMAGE_COUNT | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"
echo ""

# Write summary file
{
    echo "=== Llama Simple Test Summary ==="
    echo "Date: $(date)"
    echo "Model: $MODEL"
    echo ""
    echo "Total: $IMAGE_COUNT | Passed: $PASSED | Failed: $FAILED"
    echo ""
    echo "=== PASSED ==="
    for img in "${PASS_LIST[@]}"; do
        echo "  [PASS] $img"
    done
    echo ""
    echo "=== FAILED ==="
    for img in "${FAIL_LIST[@]}"; do
        echo "  [FAIL] $img"
    done
} > "$SUMMARY_FILE"

if [ ${#PASS_LIST[@]} -gt 0 ]; then
    echo -e "${GREEN}PASSED:${NC}"
    for img in "${PASS_LIST[@]}"; do
        echo "  $img"
    done
fi

if [ ${#FAIL_LIST[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}FAILED:${NC}"
    for img in "${FAIL_LIST[@]}"; do
        echo "  $img"
    done
fi

echo ""
echo "Full log: $RESULTS_FILE"
echo "Summary:  $SUMMARY_FILE"
