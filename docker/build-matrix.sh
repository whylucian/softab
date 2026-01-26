#!/bin/bash
# Build matrix for Strix Halo ROCm ablation studies
# Generates Docker images for all combinations of variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${REGISTRY:-localhost}"
TAG_PREFIX="${TAG_PREFIX:-softab}"

# Detect container runtime (prefer podman on Fedora)
if command -v podman &> /dev/null; then
    CONTAINER_CMD="${CONTAINER_CMD:-podman}"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="${CONTAINER_CMD:-docker}"
else
    echo "Error: Neither podman nor docker found" >&2
    exit 1
fi

# Ablation variables
FEDORA_VERSIONS=("43")
GFX_TARGETS=("gfx1100" "gfx1150" "gfx1151" "gfx1152")
ROCM_VERSIONS=("6.4.4" "7.0.1" "7.1.1")
VULKAN_DRIVERS=("AMDVLK" "RADV")
HIPBLASLT_OPTIONS=("0" "1")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Commands:
    build-all       Build all image combinations
    build-pytorch   Build PyTorch images only (PRIORITY 1)
    build-rocm      Build ROCm images only
    build-llama     Build llama.cpp images only
    build-whisper   Build whisper.cpp images only
    list            List all image tags that would be built
    clean           Remove all softab images

Options:
    --gfx TARGET    Build only for specific GFX target (default: all)
    --fedora VER    Build only for specific Fedora version (default: 43)
    --dry-run       Show what would be built without building
    --parallel N    Build N images in parallel (default: 1)
    --push          Push images after building
    -h, --help      Show this help

Examples:
    $0 build-all                    # Build everything
    $0 build-llama --gfx gfx1151   # Build llama.cpp for gfx1151 only
    $0 list                         # Show all image tags
    $0 --dry-run build-all          # Preview builds

Environment:
    REGISTRY        Docker registry (default: localhost)
    TAG_PREFIX      Image tag prefix (default: softab)
EOF
}

# Build a single image
build_image() {
    local dockerfile=$1
    local tag=$2
    shift 2
    local build_args=("$@")

    local full_tag="${REGISTRY}/${TAG_PREFIX}:${tag}"

    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would build: $full_tag"
        log_info "  Dockerfile: $dockerfile"
        log_info "  Args: ${build_args[*]}"
        return 0
    fi

    log_info "Building: $full_tag"

    local cmd=($CONTAINER_CMD build -f "$dockerfile" -t "$full_tag")
    for arg in "${build_args[@]}"; do
        cmd+=(--build-arg "$arg")
    done
    cmd+=("$SCRIPT_DIR")

    if "${cmd[@]}"; then
        log_success "Built: $full_tag"
        if [ "$PUSH" = "1" ]; then
            $CONTAINER_CMD push "$full_tag"
            log_success "Pushed: $full_tag"
        fi
        return 0
    else
        log_error "Failed: $full_tag"
        return 1
    fi
}

# Build ROCm images
build_rocm_images() {
    local targets=("${GFX_FILTER[@]:-${GFX_TARGETS[@]}}")
    local fedoras=("${FEDORA_FILTER:-${FEDORA_VERSIONS[@]}}")

    log_info "Building ROCm images..."

    for fedora in "${fedoras[@]}"; do
        for gfx in "${targets[@]}"; do
            # Fedora repo
            build_image \
                "$SCRIPT_DIR/rocm/Dockerfile.fedora-repo" \
                "rocm-fedora-repo-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"

            # AMD repo with different versions
            for rocm_ver in "${ROCM_VERSIONS[@]}"; do
                build_image \
                    "$SCRIPT_DIR/rocm/Dockerfile.amd-repo" \
                    "rocm-amd-${rocm_ver}-f${fedora}-${gfx}" \
                    "FEDORA_VERSION=$fedora" \
                    "ROCM_VERSION=$rocm_ver" \
                    "GFX_TARGET=$gfx"
            done

            # TheRock nightlies
            build_image \
                "$SCRIPT_DIR/rocm/Dockerfile.therock" \
                "rocm-therock-nightly-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"
        done
    done
}

# Build llama.cpp images
build_llama_images() {
    local targets=("${GFX_FILTER[@]:-${GFX_TARGETS[@]}}")
    local fedoras=("${FEDORA_FILTER:-${FEDORA_VERSIONS[@]}}")

    log_info "Building llama.cpp images..."

    for fedora in "${fedoras[@]}"; do
        # Vulkan builds (no GFX target needed, but test different drivers)
        for driver in "${VULKAN_DRIVERS[@]}"; do
            build_image \
                "$SCRIPT_DIR/llama-cpp/Dockerfile.vulkan" \
                "llama-vulkan-${driver,,}-f${fedora}" \
                "FEDORA_VERSION=$fedora" \
                "VULKAN_DRIVER=$driver"
        done

        # HIP builds for each GFX target
        for gfx in "${targets[@]}"; do
            # Standard HIP
            for hipblaslt in "${HIPBLASLT_OPTIONS[@]}"; do
                local lt_suffix=""
                [ "$hipblaslt" = "1" ] && lt_suffix="-hipblaslt"
                build_image \
                    "$SCRIPT_DIR/llama-cpp/Dockerfile.hip" \
                    "llama-hip${lt_suffix}-f${fedora}-${gfx}" \
                    "FEDORA_VERSION=$fedora" \
                    "GFX_TARGET=$gfx" \
                    "USE_HIPBLASLT=$hipblaslt"
            done

            # HIP + rocWMMA (Flash Attention)
            build_image \
                "$SCRIPT_DIR/llama-cpp/Dockerfile.hip-rocwmma" \
                "llama-hip-rocwmma-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"
        done
    done
}

# Build whisper.cpp images
build_whisper_images() {
    local targets=("${GFX_FILTER[@]:-${GFX_TARGETS[@]}}")
    local fedoras=("${FEDORA_FILTER:-${FEDORA_VERSIONS[@]}}")

    log_info "Building whisper.cpp images..."

    for fedora in "${fedoras[@]}"; do
        for gfx in "${targets[@]}"; do
            build_image \
                "$SCRIPT_DIR/whisper-cpp/Dockerfile.hip" \
                "whisper-hip-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"
        done
    done
}

# Build PyTorch images (PRIORITY 1)
build_pytorch_images() {
    local targets=("${GFX_FILTER[@]:-${GFX_TARGETS[@]}}")
    local fedoras=("${FEDORA_FILTER:-${FEDORA_VERSIONS[@]}}")

    log_info "Building PyTorch images..."

    for fedora in "${fedoras[@]}"; do
        # Official ROCm wheels (expected to FAIL on gfx1151)
        build_image \
            "$SCRIPT_DIR/pytorch/Dockerfile.official-rocm" \
            "pytorch-official-rocm62-f${fedora}" \
            "FEDORA_VERSION=$fedora" \
            "ROCM_VERSION=6.2"

        # Official + HSA_OVERRIDE hack
        build_image \
            "$SCRIPT_DIR/pytorch/Dockerfile.official-rocm-override" \
            "pytorch-official-override-f${fedora}" \
            "FEDORA_VERSION=$fedora" \
            "ROCM_VERSION=6.2" \
            "GFX_OVERRIDE=11.0.0"

        for gfx in "${targets[@]}"; do
            # TheRock nightlies (native gfx1151)
            build_image \
                "$SCRIPT_DIR/pytorch/Dockerfile.therock-nightly" \
                "pytorch-therock-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"

            # scottt/rocm-TheRock (recommended for CV)
            build_image \
                "$SCRIPT_DIR/pytorch/Dockerfile.scottt-therock" \
                "pytorch-scottt-f${fedora}-${gfx}" \
                "FEDORA_VERSION=$fedora" \
                "GFX_TARGET=$gfx"
        done

        # From source (optional, very slow)
        # build_image \
        #     "$SCRIPT_DIR/pytorch/Dockerfile.from-source" \
        #     "pytorch-source-f${fedora}-gfx1151" \
        #     "FEDORA_VERSION=$fedora" \
        #     "GFX_TARGET=gfx1151"
    done
}

# List all tags
list_tags() {
    local targets=("${GFX_FILTER[@]:-${GFX_TARGETS[@]}}")
    local fedoras=("${FEDORA_FILTER:-${FEDORA_VERSIONS[@]}}")

    echo "=== ROCm Images ==="
    for fedora in "${fedoras[@]}"; do
        for gfx in "${targets[@]}"; do
            echo "  ${TAG_PREFIX}:rocm-fedora-repo-f${fedora}-${gfx}"
            for rocm_ver in "${ROCM_VERSIONS[@]}"; do
                echo "  ${TAG_PREFIX}:rocm-amd-${rocm_ver}-f${fedora}-${gfx}"
            done
            echo "  ${TAG_PREFIX}:rocm-therock-nightly-f${fedora}-${gfx}"
        done
    done

    echo ""
    echo "=== llama.cpp Images ==="
    for fedora in "${fedoras[@]}"; do
        for driver in "${VULKAN_DRIVERS[@]}"; do
            echo "  ${TAG_PREFIX}:llama-vulkan-${driver,,}-f${fedora}"
        done
        for gfx in "${targets[@]}"; do
            echo "  ${TAG_PREFIX}:llama-hip-f${fedora}-${gfx}"
            echo "  ${TAG_PREFIX}:llama-hip-hipblaslt-f${fedora}-${gfx}"
            echo "  ${TAG_PREFIX}:llama-hip-rocwmma-f${fedora}-${gfx}"
        done
    done

    echo ""
    echo "=== PyTorch Images (PRIORITY 1) ==="
    for fedora in "${fedoras[@]}"; do
        echo "  ${TAG_PREFIX}:pytorch-official-rocm62-f${fedora} (expected FAIL)"
        echo "  ${TAG_PREFIX}:pytorch-official-override-f${fedora} (HSA hack)"
        for gfx in "${targets[@]}"; do
            echo "  ${TAG_PREFIX}:pytorch-therock-f${fedora}-${gfx}"
            echo "  ${TAG_PREFIX}:pytorch-scottt-f${fedora}-${gfx} (CV recommended)"
        done
    done

    echo ""
    echo "=== whisper.cpp Images ==="
    for fedora in "${fedoras[@]}"; do
        for gfx in "${targets[@]}"; do
            echo "  ${TAG_PREFIX}:whisper-hip-f${fedora}-${gfx}"
        done
    done

    # Count
    local count=0
    for fedora in "${fedoras[@]}"; do
        for gfx in "${targets[@]}"; do
            ((count += 1))  # fedora-repo
            ((count += ${#ROCM_VERSIONS[@]}))  # amd-repo versions
            ((count += 1))  # therock
            ((count += 2))  # llama hip variants
            ((count += 1))  # llama rocwmma
            ((count += 1))  # whisper
        done
        ((count += ${#VULKAN_DRIVERS[@]}))  # vulkan
    done
    echo ""
    echo "Total images: $count"
}

# Clean images
clean_images() {
    log_info "Removing ${TAG_PREFIX} images..."
    $CONTAINER_CMD images --format '{{.Repository}}:{{.Tag}}' | grep "^${REGISTRY}/${TAG_PREFIX}:" | xargs -r $CONTAINER_CMD rmi
    log_success "Cleaned"
}

# Parse arguments
DRY_RUN=0
PUSH=0
PARALLEL=1
GFX_FILTER=()
FEDORA_FILTER=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --gfx)
            GFX_FILTER=("$2")
            shift 2
            ;;
        --fedora)
            FEDORA_FILTER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --parallel)
            PARALLEL=$2
            shift 2
            ;;
        --push)
            PUSH=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        build-all|build-rocm|build-llama|build-whisper|build-pytorch|list|clean)
            COMMAND=$1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute command
case $COMMAND in
    build-all)
        build_pytorch_images  # Priority 1
        build_whisper_images  # Priority 2
        build_llama_images    # Priority 3
        build_rocm_images
        ;;
    build-pytorch)
        build_pytorch_images
        ;;
    build-rocm)
        build_rocm_images
        ;;
    build-llama)
        build_llama_images
        ;;
    build-whisper)
        build_whisper_images
        ;;
    list)
        list_tags
        ;;
    clean)
        clean_images
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
