#!/bin/bash
# Run all models on all images and aggregate results
# Usage: ./run-all-benchmarks.sh [output_dir] [pp] [tg] [r]
#   output_dir: where to save results (default: results/benchmark-TIMESTAMP)
#   pp: prompt processing tokens (default: 512)
#   tg: token generation count (default: 128)
#   r: repetitions (default: 5)
#
# Examples:
#   ./run-all-benchmarks.sh                           # defaults: pp512, tg128, r5
#   ./run-all-benchmarks.sh results/test 1024 256 3   # pp1024, tg256, r3
#   PP=2048 TG=64 R=10 ./run-all-benchmarks.sh        # via env vars

set -e

# Benchmark parameters (configurable)
PP="${PP:-${2:-512}}"
TG="${TG:-${3:-128}}"
R="${R:-${4:-5}}"

# Output directory includes parameters
BASE_DIR="${1:-results/benchmark-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_DIR="${BASE_DIR}-pp${PP}-tg${TG}-r${R}"
mkdir -p "$OUTPUT_DIR"

# Working images (tested and functional)
IMAGES=(
    "localhost/softab:llama-hipblaslt-0"
    "localhost/softab:llama-hipblaslt-1"
    "localhost/softab:llama-hip-rocm72-vram"
    "localhost/softab:llama-hip-rocm72-gfx1151"
    "localhost/softab:llama-hip-rocm72-nofa-gfx1151"
    "localhost/softab:llama-hip-rocm72-fa0-gfx1151"
    "localhost/softab:llama-hip-rocm72-mmap-gfx1151"
    "localhost/softab:llama-hip-rocm72-sdma1-gfx1151"
    "localhost/softab:llama-hip-rocwmma-rocm72-gfx1151"
    "localhost/softab:llama-vulkan-radv-ub1024"
    "localhost/softab:llama-vulkan-radv-fa-finegrain"
    "localhost/softab:llama-vulkan-radv-fa"
    "localhost/softab:llama-vulkan-radv"
    "localhost/softab:llama-vulkan"
    "localhost/softab:llama-moe"
)

# All models
MODELS=(
    "/data/models/tinyllama-1.1b-q4.gguf"
    "/data/models/LFM2-2.6B-Q4_K_M.gguf"
    "/data/models/llama3.2-3b-q8.gguf"
    "/data/models/qwen2.5-coder-7b-q6.gguf"
    "/data/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf"
    "/data/models/openai_gpt-oss-20b-Q4_K_M.gguf"
    "/data/models/GLM-4.7-Flash-Q4_K_M.gguf"
    "/data/models/Qwen3-30B-A3B-Q4_K_M.gguf"
    "/data/models/Qwen2.5-32B-Instruct-Q4_K_M.gguf"
    "/data/models/Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf"
    "/data/models/Qwen3-Next-80B-A3B-Instruct-Q4_K_M.gguf"
    "/data/models/openai_gpt-oss-120b-Q4_K_M-00001-of-00002.gguf"
    "/data/models/Qwen3-235B-A22B-Q3_K_M-00001-of-00003.gguf"
)

# CSV header with dynamic column names
RESULTS_CSV="$OUTPUT_DIR/results-pp${PP}-tg${TG}-r${R}.csv"
echo "image,model,size_gib,params_b,backend,pp${PP},tg${TG},status" > "$RESULTS_CSV"

# Summary file
SUMMARY_FILE="$OUTPUT_DIR/summary-pp${PP}-tg${TG}-r${R}.md"

# Config file to record parameters
CONFIG_FILE="$OUTPUT_DIR/config.txt"
cat > "$CONFIG_FILE" << EOF
Benchmark Configuration
=======================
Date: $(date)
PP (prompt tokens): $PP
TG (generation tokens): $TG
R (repetitions): $R
Output directory: $OUTPUT_DIR
EOF

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

get_image_short_name() {
    echo "$1" | sed 's|localhost/softab:||'
}

get_model_short_name() {
    basename "$1" .gguf | sed 's/-Q[0-9].*//; s/_Q[0-9].*//'
}

run_benchmark() {
    local image="$1"
    local model="$2"
    local image_short=$(get_image_short_name "$image")
    local model_short=$(get_model_short_name "$model")
    local output_file="$OUTPUT_DIR/${image_short}__${model_short}__pp${PP}-tg${TG}-r${R}.txt"

    log "Benchmarking: $image_short + $model_short (pp$PP tg$TG r$R)"

    # Determine container flags
    local container_flags="--device=/dev/dri --security-opt seccomp=unconfined --security-opt label=disable"
    if [[ "$image" == *"hip"* ]] || [[ "$image" == *"rocm"* ]]; then
        container_flags="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"
    fi

    # Run benchmark with configurable parameters
    if timeout 600 podman run --rm \
        $container_flags \
        -e HSA_ENABLE_SDMA=0 \
        -e GPU_MAX_HEAP_SIZE=100 \
        -v "$(dirname $model):/models:ro" \
        "$image" \
        llama-bench \
            --model "/models/$(basename $model)" \
            -ngl 999 \
            -p "$PP" \
            -n "$TG" \
            -r "$R" 2>&1 > "$output_file"; then

        # Parse results - match the actual pp/tg values used
        local pp_line=$(grep -E "pp${PP}" "$output_file" | grep "^\|" | tail -1)
        local tg_line=$(grep -E "tg${TG}" "$output_file" | grep "^\|" | tail -1)

        if [ -n "$pp_line" ] && [ -n "$tg_line" ]; then
            # Extract values using awk (fields: 1=empty, 2=model, 3=size, 4=params, 5=backend, 6=ngl, 7=test, 8=t/s)
            local size=$(echo "$pp_line" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')
            local params=$(echo "$pp_line" | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}')
            local backend=$(echo "$pp_line" | awk -F'|' '{gsub(/^ +| +$/, "", $5); print $5}')
            local pp_val=$(echo "$pp_line" | awk -F'|' '{gsub(/^ +| +$/, "", $8); split($8, a, " "); print a[1]}')
            local tg_val=$(echo "$tg_line" | awk -F'|' '{gsub(/^ +| +$/, "", $8); split($8, a, " "); print a[1]}')

            echo "$image_short,$model_short,$size,$params,$backend,$pp_val,$tg_val,success" >> "$RESULTS_CSV"
            log "  -> pp${PP}: $pp_val t/s, tg${TG}: $tg_val t/s ($backend)"
            return 0
        else
            echo "$image_short,$model_short,,,,,failed_parse" >> "$RESULTS_CSV"
            log "  -> Failed to parse results"
            return 1
        fi
    else
        echo "$image_short,$model_short,,,,,failed_run" >> "$RESULTS_CSV"
        log "  -> Benchmark failed or timed out"
        return 1
    fi
}

generate_summary() {
    log "Generating summary table..."

    cat > "$SUMMARY_FILE" << EOF
# Benchmark Results

Generated: $(date)
GPU: AMD Radeon 8060S (gfx1151)

## Parameters
- **Prompt tokens (pp):** $PP
- **Generation tokens (tg):** $TG
- **Repetitions (r):** $R

## Results by Model

EOF

    # Get unique models
    local models=$(tail -n +2 "$RESULTS_CSV" | cut -d',' -f2 | sort -u)

    for model in $models; do
        echo "### $model" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "| Image | Backend | pp${PP} (t/s) | tg${TG} (t/s) |" >> "$SUMMARY_FILE"
        echo "|-------|---------|-------------|-------------|" >> "$SUMMARY_FILE"

        grep ",$model," "$RESULTS_CSV" | sort -t',' -k6 -rn | while IFS=',' read -r image m size params backend pp_val tg_val status; do
            if [ "$status" = "success" ]; then
                echo "| $image | $backend | $pp_val | $tg_val |" >> "$SUMMARY_FILE"
            fi
        done
        echo "" >> "$SUMMARY_FILE"
    done

    # Generate pivot table (model x image)
    echo "## Summary Table (pp${PP} / tg${TG})" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"

    # Get unique images for header
    local images=$(tail -n +2 "$RESULTS_CSV" | cut -d',' -f1 | sort -u)

    # Header row
    printf "| Model |" >> "$SUMMARY_FILE"
    for img in $images; do
        printf " %s |" "$img" >> "$SUMMARY_FILE"
    done
    echo "" >> "$SUMMARY_FILE"

    # Separator
    printf "|-------|" >> "$SUMMARY_FILE"
    for img in $images; do
        printf "-------------|" >> "$SUMMARY_FILE"
    done
    echo "" >> "$SUMMARY_FILE"

    # Data rows
    for model in $models; do
        printf "| %s |" "$model" >> "$SUMMARY_FILE"
        for img in $images; do
            local result=$(grep "^$img,$model," "$RESULTS_CSV" | head -1)
            if [ -n "$result" ]; then
                local pp=$(echo "$result" | cut -d',' -f6)
                local tg=$(echo "$result" | cut -d',' -f7)
                local status=$(echo "$result" | cut -d',' -f8)
                if [ "$status" = "success" ]; then
                    printf " %s/%s |" "$pp" "$tg" >> "$SUMMARY_FILE"
                else
                    printf " - |" >> "$SUMMARY_FILE"
                fi
            else
                printf " - |" >> "$SUMMARY_FILE"
            fi
        done
        echo "" >> "$SUMMARY_FILE"
    done

    log "Summary written to $SUMMARY_FILE"
}

# Main execution
log "Starting benchmark suite"
log "Parameters: pp=$PP, tg=$TG, r=$R"
log "Output directory: $OUTPUT_DIR"
log "Images: ${#IMAGES[@]}"
log "Models: ${#MODELS[@]}"
log "Total combinations: $((${#IMAGES[@]} * ${#MODELS[@]}))"
echo ""

total=$((${#IMAGES[@]} * ${#MODELS[@]}))
current=0

for model in "${MODELS[@]}"; do
    if [ ! -f "$model" ]; then
        log "WARNING: Model not found: $model"
        continue
    fi

    for image in "${IMAGES[@]}"; do
        current=$((current + 1))
        log "[$current/$total] Running benchmark..."
        run_benchmark "$image" "$model" || true
    done
done

echo ""
generate_summary

log "Benchmark suite complete!"
log "Results CSV: $RESULTS_CSV"
log "Summary: $SUMMARY_FILE"
log "Config: $CONFIG_FILE"
