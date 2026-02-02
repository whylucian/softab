#!/bin/bash
# Quick benchmark - runs a subset of models on best-performing images
# Usage: ./run-quick-benchmark.sh [output_dir] [pp] [tg] [r]
#
# Examples:
#   ./run-quick-benchmark.sh                           # defaults: pp512, tg128, r5
#   ./run-quick-benchmark.sh results/quick 1024 256 3  # pp1024, tg256, r3
#   PP=2048 TG=64 R=10 ./run-quick-benchmark.sh        # via env vars

set -e

# Benchmark parameters (configurable)
PP="${PP:-${2:-512}}"
TG="${TG:-${3:-128}}"
R="${R:-${4:-5}}"

# Output directory includes parameters
BASE_DIR="${1:-results/quick-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_DIR="${BASE_DIR}-pp${PP}-tg${TG}-r${R}"
mkdir -p "$OUTPUT_DIR"

# Best performing images only
IMAGES=(
    "localhost/softab:llama-hipblaslt-0"
    "localhost/softab:llama-hip-rocm72-vram"
    "localhost/softab:llama-vulkan-radv-fa-finegrain"
    "localhost/softab:llama-vulkan-radv-ub1024"
)

# Quick model set (small to medium)
MODELS=(
    "/data/models/Qwen3-30B-A3B-Q4_K_M.gguf"
    "/data/models/openai_gpt-oss-20b-Q4_K_M.gguf"
    "/data/models/Qwen2.5-14B-Instruct-Q4_K_M.gguf"
)

# CSV header with dynamic column names
RESULTS_CSV="$OUTPUT_DIR/results-pp${PP}-tg${TG}-r${R}.csv"
echo "image,model,size_gib,params_b,backend,pp${PP},tg${TG},status" > "$RESULTS_CSV"

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

    local container_flags="--device=/dev/dri --security-opt seccomp=unconfined --security-opt label=disable"
    if [[ "$image" == *"hip"* ]] || [[ "$image" == *"rocm"* ]]; then
        container_flags="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"
    fi

    if timeout 300 podman run --rm \
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
        else
            echo "$image_short,$model_short,,,,,failed_parse" >> "$RESULTS_CSV"
        fi
    else
        echo "$image_short,$model_short,,,,,failed_run" >> "$RESULTS_CSV"
    fi
}

log "Quick benchmark starting..."
log "Parameters: pp=$PP, tg=$TG, r=$R"
log "Output: $OUTPUT_DIR"

for model in "${MODELS[@]}"; do
    for image in "${IMAGES[@]}"; do
        run_benchmark "$image" "$model" || true
    done
done

echo ""
echo "=== Results ==="
column -t -s',' "$RESULTS_CSV"

log "Done! Results in $RESULTS_CSV"
