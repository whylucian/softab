#!/bin/bash
# Strix Halo Ablation Test Suite
# Collects system info and runs benchmarks, outputs structured JSON results

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$(dirname "$SCRIPT_DIR")/results}"
SAMPLES_DIR="${SAMPLES_DIR:-$(dirname "$SCRIPT_DIR")/samples}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_ID="${RUN_ID:-run_${TIMESTAMP}}"
RESULT_FILE="${RESULTS_DIR}/${RUN_ID}.json"

# Test configuration
MEMORY_LIMIT_GB="${MEMORY_LIMIT_GB:-16}"  # Limit memory to stress test
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}" # 5 min timeout per test

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1" >&2; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

# Initialize result structure
init_results() {
    mkdir -p "$RESULTS_DIR"
    cat > "$RESULT_FILE" << EOF
{
  "run_id": "${RUN_ID}",
  "timestamp": "$(date -Iseconds)",
  "system": {},
  "environment": {},
  "benchmarks": {},
  "errors": []
}
EOF
}

# Update JSON result file
update_result() {
    local key=$1
    local value=$2
    local tmp=$(mktemp)
    jq --argjson val "$value" ".$key = \$val" "$RESULT_FILE" > "$tmp" && mv "$tmp" "$RESULT_FILE"
}

# Append to errors array
append_error() {
    local error=$1
    local tmp=$(mktemp)
    jq --arg err "$error" '.errors += [$err]' "$RESULT_FILE" > "$tmp" && mv "$tmp" "$RESULT_FILE"
}

# Run a test with timeout and error capture
run_test() {
    local name=$1
    local cmd=$2
    local timeout_sec=${3:-$TIMEOUT_SECONDS}

    log_info "Running: $name"

    local start_time=$(date +%s.%N)
    local output
    local exit_code

    output=$(timeout "$timeout_sec" bash -c "$cmd" 2>&1)
    exit_code=$?

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    if [ $exit_code -eq 0 ]; then
        log_success "$name (${duration}s)"
    elif [ $exit_code -eq 124 ]; then
        log_fail "$name: TIMEOUT after ${timeout_sec}s"
        append_error "Test '$name' timed out after ${timeout_sec}s"
    else
        log_fail "$name: exit code $exit_code"
        append_error "Test '$name' failed with exit code $exit_code: $(echo "$output" | tail -5)"
    fi

    echo "$output"
    return $exit_code
}

# Collect system information
collect_system_info() {
    log_info "Collecting system information..."

    local system_info=$(cat << EOF
{
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "kernel_full": "$(uname -a)",
  "arch": "$(uname -m)",
  "distro": "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)",
  "distro_id": "$(cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d'=' -f2)",
  "cpu_model": "$(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)",
  "cpu_cores": $(nproc),
  "memory_total_gb": $(free -g | awk '/Mem:/ {print $2}'),
  "memory_available_gb": $(free -g | awk '/Mem:/ {print $7}'),
  "boot_params": "$(cat /proc/cmdline | tr ' ' '\n' | grep -E 'amd|ttm|iommu' | tr '\n' ' ')"
}
EOF
)
    update_result "system" "$system_info"
}

# Collect ROCm/GPU information
collect_gpu_info() {
    log_info "Collecting GPU information..."

    local gpu_info='{"available": false}'

    if command -v rocminfo &> /dev/null; then
        local rocm_version=$(cat /opt/rocm/.info/version 2>/dev/null || hipconfig --version 2>/dev/null || echo "unknown")
        local gpu_name=$(rocminfo 2>/dev/null | grep "Marketing Name" | head -1 | sed 's/.*: //' | xargs)
        local gfx_version=$(rocminfo 2>/dev/null | grep "Name:" | grep gfx | head -1 | awk '{print $2}')
        local compute_units=$(rocminfo 2>/dev/null | grep "Compute Unit:" | head -1 | awk '{print $3}')

        gpu_info=$(cat << EOF
{
  "available": true,
  "rocm_version": "$rocm_version",
  "gpu_name": "$gpu_name",
  "gfx_version": "$gfx_version",
  "compute_units": "$compute_units",
  "rocm_path": "${ROCM_PATH:-/opt/rocm}"
}
EOF
)
    fi

    # Add Vulkan info
    if command -v vulkaninfo &> /dev/null; then
        local vk_device=$(vulkaninfo 2>/dev/null | grep "deviceName" | head -1 | sed 's/.*= //')
        local vk_driver=$(vulkaninfo 2>/dev/null | grep "driverName" | head -1 | sed 's/.*= //')
        gpu_info=$(echo "$gpu_info" | jq --arg vk "$vk_device" --arg drv "$vk_driver" '. + {vulkan_device: $vk, vulkan_driver: $drv}')
    fi

    update_result "system.gpu" "$gpu_info"
}

# Collect environment variables
collect_environment() {
    log_info "Collecting environment variables..."

    local env_info=$(cat << EOF
{
  "HSA_ENABLE_SDMA": "${HSA_ENABLE_SDMA:-unset}",
  "ROCBLAS_USE_HIPBLASLT": "${ROCBLAS_USE_HIPBLASLT:-unset}",
  "PYTORCH_HIP_ALLOC_CONF": "${PYTORCH_HIP_ALLOC_CONF:-unset}",
  "AMD_VULKAN_ICD": "${AMD_VULKAN_ICD:-unset}",
  "GPU_TARGETS": "${GPU_TARGETS:-unset}",
  "AMDGPU_TARGETS": "${AMDGPU_TARGETS:-unset}",
  "HIP_VISIBLE_DEVICES": "${HIP_VISIBLE_DEVICES:-unset}",
  "GGML_CUDA_ENABLE_UNIFIED_MEMORY": "${GGML_CUDA_ENABLE_UNIFIED_MEMORY:-unset}",
  "GGML_VK_PREFER_HOST_MEMORY": "${GGML_VK_PREFER_HOST_MEMORY:-unset}",
  "PATH": "$PATH",
  "LD_LIBRARY_PATH": "${LD_LIBRARY_PATH:-unset}"
}
EOF
)
    update_result "environment" "$env_info"
}

# GTT/Memory info
collect_memory_info() {
    log_info "Collecting GPU memory information..."

    local mem_info='{"gtt_available": false}'

    if [ -f /sys/class/drm/card0/device/mem_info_gtt_total ]; then
        local gtt_total=$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | head -1)
        local gtt_used=$(cat /sys/class/drm/card*/device/mem_info_gtt_used 2>/dev/null | head -1)
        local vram_total=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)

        mem_info=$(cat << EOF
{
  "gtt_available": true,
  "gtt_total_bytes": $gtt_total,
  "gtt_total_gb": $(echo "scale=2; $gtt_total / 1024 / 1024 / 1024" | bc),
  "gtt_used_bytes": ${gtt_used:-0},
  "vram_total_bytes": ${vram_total:-0}
}
EOF
)
    fi

    update_result "system.gpu_memory" "$mem_info"
}

# Matrix multiplication benchmark (PyTorch)
benchmark_matmul() {
    log_info "Running matrix multiplication benchmark..."

    if ! python3 -c "import torch" 2>/dev/null; then
        log_warn "PyTorch not available, skipping matmul benchmark"
        update_result "benchmarks.matmul" '{"status": "skipped", "reason": "pytorch not available"}'
        return 0
    fi

    local output
    output=$(run_test "matmul" "python3 ${SCRIPT_DIR}/bench_matmul.py --memory-limit ${MEMORY_LIMIT_GB}" 120)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Parse the JSON output from the benchmark
        local result=$(echo "$output" | grep -E '^\{' | tail -1)
        if [ -n "$result" ]; then
            update_result "benchmarks.matmul" "$result"
        fi
    else
        update_result "benchmarks.matmul" '{"status": "failed", "exit_code": '$exit_code'}'
    fi
}

# Whisper benchmark
benchmark_whisper() {
    log_info "Running whisper.cpp benchmark..."

    local audio_file="${SAMPLES_DIR}/test_audio.wav"

    if [ ! -f "$audio_file" ]; then
        log_warn "Audio sample not found at $audio_file"
        update_result "benchmarks.whisper" '{"status": "skipped", "reason": "audio sample not found"}'
        return 0
    fi

    if ! command -v whisper-cli &> /dev/null; then
        log_warn "whisper-cli not found, skipping whisper benchmark"
        update_result "benchmarks.whisper" '{"status": "skipped", "reason": "whisper-cli not found"}'
        return 0
    fi

    local model="${WHISPER_MODEL:-/whisper.cpp/models/ggml-base.en.bin}"
    if [ ! -f "$model" ]; then
        log_warn "Whisper model not found at $model"
        update_result "benchmarks.whisper" '{"status": "skipped", "reason": "model not found"}'
        return 0
    fi

    local start_time=$(date +%s.%N)
    local output
    output=$(run_test "whisper" "whisper-cli -m '$model' -f '$audio_file' 2>&1" 600)
    local exit_code=$?
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    # Get audio duration
    local audio_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null || echo "unknown")

    if [ $exit_code -eq 0 ]; then
        local speedup="unknown"
        if [ "$audio_duration" != "unknown" ]; then
            speedup=$(echo "scale=2; $audio_duration / $duration" | bc)
        fi

        update_result "benchmarks.whisper" "$(cat << EOF
{
  "status": "success",
  "audio_duration_sec": $audio_duration,
  "processing_time_sec": $duration,
  "speedup": $speedup,
  "model": "$model"
}
EOF
)"
    else
        update_result "benchmarks.whisper" '{"status": "failed", "exit_code": '$exit_code'}'
    fi
}

# llama.cpp benchmark
benchmark_llama() {
    log_info "Running llama.cpp benchmark..."

    if ! command -v llama-bench &> /dev/null; then
        log_warn "llama-bench not found, skipping llama benchmark"
        update_result "benchmarks.llama" '{"status": "skipped", "reason": "llama-bench not found"}'
        return 0
    fi

    local model="${LLAMA_MODEL:-}"
    if [ -z "$model" ] || [ ! -f "$model" ]; then
        log_warn "LLAMA_MODEL not set or not found"
        update_result "benchmarks.llama" '{"status": "skipped", "reason": "model not found"}'
        return 0
    fi

    local output
    output=$(run_test "llama-bench" "llama-bench --mmap 0 -ngl 999 -fa 1 -m '$model' -p 512,1024,2048 -n 32 2>&1" 300)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Parse llama-bench output (it's a table)
        update_result "benchmarks.llama" "$(cat << EOF
{
  "status": "success",
  "model": "$model",
  "raw_output": $(echo "$output" | jq -Rs .)
}
EOF
)"
    else
        update_result "benchmarks.llama" '{"status": "failed", "exit_code": '$exit_code'}'
    fi
}

# ROCm stress test
benchmark_rocm_stress() {
    log_info "Running ROCm stress test..."

    if ! command -v rocminfo &> /dev/null; then
        log_warn "ROCm not available, skipping stress test"
        update_result "benchmarks.rocm_stress" '{"status": "skipped", "reason": "rocm not available"}'
        return 0
    fi

    local output
    output=$(run_test "rocm_stress" "python3 ${SCRIPT_DIR}/bench_stress.py --duration 30 --memory-limit ${MEMORY_LIMIT_GB}" 60)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        local result=$(echo "$output" | grep -E '^\{' | tail -1)
        if [ -n "$result" ]; then
            update_result "benchmarks.rocm_stress" "$result"
        fi
    else
        update_result "benchmarks.rocm_stress" '{"status": "failed", "exit_code": '$exit_code'}'
    fi
}

# Print summary
print_summary() {
    echo ""
    log_info "========================================="
    log_info "Test Suite Complete"
    log_info "========================================="
    log_info "Results saved to: $RESULT_FILE"
    echo ""

    # Count errors
    local error_count=$(jq '.errors | length' "$RESULT_FILE")
    if [ "$error_count" -gt 0 ]; then
        log_fail "Errors encountered: $error_count"
        jq -r '.errors[]' "$RESULT_FILE" | while read -r err; do
            echo "  - $err" >&2
        done
    else
        log_success "All tests completed without errors"
    fi

    echo ""
    log_info "Quick view: jq . $RESULT_FILE"
}

# Main
main() {
    log_info "Starting Strix Halo Ablation Test Suite"
    log_info "Run ID: $RUN_ID"
    log_info "Memory limit: ${MEMORY_LIMIT_GB}GB"
    echo ""

    init_results

    # Collect system info
    collect_system_info
    collect_gpu_info
    collect_memory_info
    collect_environment

    # Run benchmarks
    benchmark_matmul
    benchmark_whisper
    benchmark_llama
    benchmark_rocm_stress

    print_summary
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --run-id)
            RUN_ID=$2
            shift 2
            ;;
        --memory-limit)
            MEMORY_LIMIT_GB=$2
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR=$2
            shift 2
            ;;
        --samples-dir)
            SAMPLES_DIR=$2
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --run-id ID         Set run identifier (default: run_TIMESTAMP)"
            echo "  --memory-limit GB   Memory limit for tests in GB (default: 16)"
            echo "  --results-dir DIR   Directory for results (default: ../results)"
            echo "  --samples-dir DIR   Directory for audio samples (default: ../samples)"
            echo ""
            echo "Environment variables:"
            echo "  WHISPER_MODEL       Path to whisper model"
            echo "  LLAMA_MODEL         Path to llama model"
            exit 0
            ;;
        *)
            log_warn "Unknown option: $1"
            shift
            ;;
    esac
done

main
