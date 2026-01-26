#!/bin/bash
# Build Docker images with error detection and run test suite
# Captures build failures, stage information, and test results

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="${PROJECT_DIR}/docker"
RESULTS_DIR="${PROJECT_DIR}/results"
LOGS_DIR="${RESULTS_DIR}/build_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPERIMENT_ID="${EXPERIMENT_ID:-exp_${TIMESTAMP}}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Initialize experiment tracking
init_experiment() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    local manifest="${RESULTS_DIR}/${EXPERIMENT_ID}_manifest.json"
    cat > "$manifest" << EOF
{
  "experiment_id": "${EXPERIMENT_ID}",
  "started_at": "$(date -Iseconds)",
  "host_kernel": "$(uname -r)",
  "host_distro": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)",
  "builds": [],
  "tests": [],
  "summary": {
    "total_builds": 0,
    "successful_builds": 0,
    "failed_builds": 0,
    "total_tests": 0,
    "passed_tests": 0,
    "failed_tests": 0
  }
}
EOF
    echo "$manifest"
}

# Update manifest file
update_manifest() {
    local manifest=$1
    local key=$2
    local value=$3
    local tmp=$(mktemp)
    jq --argjson val "$value" ".$key = \$val" "$manifest" > "$tmp" && mv "$tmp" "$manifest"
}

# Append to manifest array
append_to_manifest() {
    local manifest=$1
    local key=$2
    local value=$3
    local tmp=$(mktemp)
    jq --argjson val "$value" ".$key += [\$val]" "$manifest" > "$tmp" && mv "$tmp" "$manifest"
}

# Parse Docker build output to detect failure stage
parse_build_failure() {
    local log_file=$1

    # Look for the last successful step
    local last_step=$(grep -E "^#[0-9]+ \[" "$log_file" | tail -1)

    # Look for error patterns
    local error_line=$(grep -n -E "(error:|Error:|ERROR|failed|FAILED|cannot|Cannot)" "$log_file" | tail -5)

    # Look for specific failure types
    local failure_type="unknown"

    if grep -q "No match for argument" "$log_file"; then
        failure_type="package_not_found"
    elif grep -q "Could not resolve host" "$log_file"; then
        failure_type="network_error"
    elif grep -q "cmake.*error" "$log_file"; then
        failure_type="cmake_error"
    elif grep -q "ninja.*error\|make.*Error" "$log_file"; then
        failure_type="compilation_error"
    elif grep -q "hipcc.*error\|amdclang.*error" "$log_file"; then
        failure_type="hip_compiler_error"
    elif grep -q "gfx[0-9]*.*not supported\|unsupported.*gfx" "$log_file"; then
        failure_type="gfx_target_unsupported"
    elif grep -q "out of memory\|OOM\|Cannot allocate" "$log_file"; then
        failure_type="memory_error"
    elif grep -q "permission denied\|Permission denied" "$log_file"; then
        failure_type="permission_error"
    fi

    cat << EOF
{
  "last_successful_step": $(echo "$last_step" | jq -Rs .),
  "failure_type": "$failure_type",
  "error_context": $(echo "$error_line" | jq -Rs .)
}
EOF
}

# Build a single Docker image with error capture
build_image_with_logging() {
    local manifest=$1
    local dockerfile=$2
    local tag=$3
    shift 3
    local build_args=("$@")

    local build_id="${tag//[:\/]/_}"
    local log_file="${LOGS_DIR}/${build_id}.log"
    local start_time=$(date +%s)

    log_info "Building: $tag"
    log_info "  Dockerfile: $dockerfile"
    log_info "  Log: $log_file"

    # Construct build command
    local cmd=(docker build -f "$dockerfile" -t "$tag" --progress=plain)
    for arg in "${build_args[@]}"; do
        cmd+=(--build-arg "$arg")
    done
    cmd+=("$DOCKER_DIR")

    # Run build and capture output
    local exit_code
    "${cmd[@]}" 2>&1 | tee "$log_file"
    exit_code=${PIPESTATUS[0]}

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Create build record
    local build_record
    if [ $exit_code -eq 0 ]; then
        log_success "Built: $tag (${duration}s)"
        build_record=$(cat << EOF
{
  "tag": "$tag",
  "dockerfile": "$dockerfile",
  "build_args": $(printf '%s\n' "${build_args[@]}" | jq -R . | jq -s .),
  "status": "success",
  "exit_code": 0,
  "duration_sec": $duration,
  "log_file": "$log_file"
}
EOF
)
        # Update summary
        local current=$(jq '.summary.successful_builds' "$manifest")
        update_manifest "$manifest" "summary.successful_builds" "$((current + 1))"
    else
        log_fail "Build failed: $tag (exit code $exit_code)"

        local failure_info=$(parse_build_failure "$log_file")

        build_record=$(cat << EOF
{
  "tag": "$tag",
  "dockerfile": "$dockerfile",
  "build_args": $(printf '%s\n' "${build_args[@]}" | jq -R . | jq -s .),
  "status": "failed",
  "exit_code": $exit_code,
  "duration_sec": $duration,
  "log_file": "$log_file",
  "failure_analysis": $failure_info
}
EOF
)
        # Update summary
        local current=$(jq '.summary.failed_builds' "$manifest")
        update_manifest "$manifest" "summary.failed_builds" "$((current + 1))"
    fi

    # Update total and append record
    local total=$(jq '.summary.total_builds' "$manifest")
    update_manifest "$manifest" "summary.total_builds" "$((total + 1))"
    append_to_manifest "$manifest" "builds" "$build_record"

    return $exit_code
}

# Run test suite in container
run_tests_in_container() {
    local manifest=$1
    local image_tag=$2
    local run_id=$3

    log_info "Running tests in: $image_tag"

    local test_result_file="${RESULTS_DIR}/${run_id}.json"
    local log_file="${LOGS_DIR}/${run_id}_test.log"
    local start_time=$(date +%s)

    # Run the test suite inside the container
    local exit_code
    docker run --rm \
        --device=/dev/kfd \
        --device=/dev/dri \
        --group-add video \
        --group-add render \
        --security-opt seccomp=unconfined \
        -v "${PROJECT_DIR}/tests:/tests:ro" \
        -v "${PROJECT_DIR}/samples:/samples:ro" \
        -v "${RESULTS_DIR}:/results" \
        -e "RUN_ID=${run_id}" \
        -e "RESULTS_DIR=/results" \
        -e "SAMPLES_DIR=/samples" \
        "$image_tag" \
        bash /tests/run-suite.sh 2>&1 | tee "$log_file"
    exit_code=${PIPESTATUS[0]}

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Create test record
    local test_record
    if [ $exit_code -eq 0 ] && [ -f "$test_result_file" ]; then
        log_success "Tests completed: $run_id (${duration}s)"

        # Extract summary from test results
        local test_errors=$(jq '.errors | length' "$test_result_file" 2>/dev/null || echo "0")

        test_record=$(cat << EOF
{
  "run_id": "$run_id",
  "image_tag": "$image_tag",
  "status": "completed",
  "errors": $test_errors,
  "duration_sec": $duration,
  "result_file": "$test_result_file",
  "log_file": "$log_file"
}
EOF
)
        if [ "$test_errors" -eq 0 ]; then
            local passed=$(jq '.summary.passed_tests' "$manifest")
            update_manifest "$manifest" "summary.passed_tests" "$((passed + 1))"
        else
            local failed=$(jq '.summary.failed_tests' "$manifest")
            update_manifest "$manifest" "summary.failed_tests" "$((failed + 1))"
        fi
    else
        log_fail "Tests failed: $run_id"
        test_record=$(cat << EOF
{
  "run_id": "$run_id",
  "image_tag": "$image_tag",
  "status": "failed",
  "exit_code": $exit_code,
  "duration_sec": $duration,
  "log_file": "$log_file"
}
EOF
)
        local failed=$(jq '.summary.failed_tests' "$manifest")
        update_manifest "$manifest" "summary.failed_tests" "$((failed + 1))"
    fi

    local total=$(jq '.summary.total_tests' "$manifest")
    update_manifest "$manifest" "summary.total_tests" "$((total + 1))"
    append_to_manifest "$manifest" "tests" "$test_record"

    return $exit_code
}

# Build and test a single configuration
build_and_test() {
    local manifest=$1
    local dockerfile=$2
    local tag=$3
    shift 3
    local build_args=("$@")

    # Build
    if build_image_with_logging "$manifest" "$dockerfile" "$tag" "${build_args[@]}"; then
        # Test
        local run_id="${tag//[:\/]/_}_test"
        run_tests_in_container "$manifest" "$tag" "$run_id"
    else
        log_warn "Skipping tests due to build failure: $tag"
    fi
}

# Print experiment summary
print_summary() {
    local manifest=$1

    echo ""
    log_info "========================================="
    log_info "Experiment Summary: $EXPERIMENT_ID"
    log_info "========================================="

    echo ""
    echo "Builds:"
    echo "  Total:      $(jq '.summary.total_builds' "$manifest")"
    echo "  Successful: $(jq '.summary.successful_builds' "$manifest")"
    echo "  Failed:     $(jq '.summary.failed_builds' "$manifest")"

    echo ""
    echo "Tests:"
    echo "  Total:  $(jq '.summary.total_tests' "$manifest")"
    echo "  Passed: $(jq '.summary.passed_tests' "$manifest")"
    echo "  Failed: $(jq '.summary.failed_tests' "$manifest")"

    # Show failed builds
    local failed_builds=$(jq -r '.builds[] | select(.status == "failed") | .tag' "$manifest")
    if [ -n "$failed_builds" ]; then
        echo ""
        log_fail "Failed builds:"
        echo "$failed_builds" | while read -r tag; do
            echo "  - $tag"
            local failure_type=$(jq -r ".builds[] | select(.tag == \"$tag\") | .failure_analysis.failure_type" "$manifest")
            echo "    Failure type: $failure_type"
        done
    fi

    echo ""
    log_info "Manifest: $manifest"
    log_info "Logs: $LOGS_DIR"
}

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

Commands:
    single DOCKERFILE TAG [BUILD_ARGS...]   Build and test a single image
    matrix                                  Build and test the full matrix
    test-only TAG                           Run tests on existing image

Options:
    --experiment-id ID   Set experiment identifier
    --skip-tests         Build only, skip tests
    -h, --help           Show this help

Examples:
    $0 single docker/llama-cpp/Dockerfile.vulkan mytest:vulkan
    $0 --experiment-id myexp matrix
    $0 test-only localhost/softab:llama-hip-f43-gfx1151
EOF
}

# Main
SKIP_TESTS=0
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --experiment-id)
            EXPERIMENT_ID=$2
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        single|matrix|test-only)
            COMMAND=$1
            shift
            ARGS=("$@")
            break
            ;;
        *)
            log_warn "Unknown option: $1"
            shift
            ;;
    esac
done

case $COMMAND in
    single)
        if [ ${#ARGS[@]} -lt 2 ]; then
            log_fail "single requires DOCKERFILE and TAG"
            exit 1
        fi
        manifest=$(init_experiment)
        build_and_test "$manifest" "${ARGS[0]}" "${ARGS[1]}" "${ARGS[@]:2}"
        print_summary "$manifest"
        ;;
    matrix)
        manifest=$(init_experiment)
        log_info "Running full build matrix..."
        # This would iterate through all combinations
        # For now, just show what would happen
        log_warn "Full matrix not yet implemented - use 'single' for individual builds"
        print_summary "$manifest"
        ;;
    test-only)
        if [ ${#ARGS[@]} -lt 1 ]; then
            log_fail "test-only requires image TAG"
            exit 1
        fi
        manifest=$(init_experiment)
        run_tests_in_container "$manifest" "${ARGS[0]}" "test_${ARGS[0]//[:\/]/_}"
        print_summary "$manifest"
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        log_fail "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
