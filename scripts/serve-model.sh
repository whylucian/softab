#!/bin/bash
# Launch llama.cpp server with a given model using softab images
# Default image: llama-vulkan-radv-ub1024

set -e

# Defaults
DEFAULT_IMAGE="localhost/softab:llama-vulkan-radv-ub1024"
DEFAULT_PORT=8080
DEFAULT_CTX=4096
DEFAULT_NGL=999
DEFAULT_TEMPLATE="chatml"

# Parse arguments
MODEL=""
IMAGE="$DEFAULT_IMAGE"
PORT="$DEFAULT_PORT"
CTX="$DEFAULT_CTX"
NGL="$DEFAULT_NGL"
TEMPLATE="$DEFAULT_TEMPLATE"
EXTRA_ARGS=""

usage() {
    cat << EOF
Usage: $0 -m MODEL_PATH [OPTIONS]

Launch llama.cpp server with a softab container image.

Required:
    -m, --model PATH      Path to GGUF model file

Options:
    -i, --image IMAGE     Container image (default: $DEFAULT_IMAGE)
    -p, --port PORT       Server port (default: $DEFAULT_PORT)
    -c, --ctx-size SIZE   Context size (default: $DEFAULT_CTX)
    -n, --ngl LAYERS      GPU layers (default: $DEFAULT_NGL, all)
    -t, --template NAME   Chat template (default: $DEFAULT_TEMPLATE, use "auto" for model default)
    -e, --extra "ARGS"    Extra llama-server arguments
    -l, --list            List available softab llama images
    -h, --help            Show this help

Examples:
    $0 -m ~/models/qwen3-30b-a3b-q4.gguf
    $0 -m ~/models/llama.gguf -i localhost/softab:llama-hip-rocm72-gfx1151 -c 8192
    $0 -m ~/models/model.gguf -p 8000 -e "--flash-attn"

Available images:
    llama-vulkan-radv-ub1024     Vulkan RADV (default, good for Strix Halo)
    llama-vulkan-amdvlk-ub512    Vulkan AMDVLK
    llama-hip-rocm72-*           HIP/ROCm variants
    llama-moe                    MoE optimized
EOF
    exit 0
}

list_images() {
    echo "Available softab llama images:"
    echo ""
    podman images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | grep -E 'softab.*llama' | sort
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--model)
            MODEL="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -c|--ctx-size)
            CTX="$2"
            shift 2
            ;;
        -n|--ngl)
            NGL="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE="$2"
            shift 2
            ;;
        -e|--extra)
            EXTRA_ARGS="$2"
            shift 2
            ;;
        -l|--list)
            list_images
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$MODEL" ]; then
    echo "Error: Model path required (-m)"
    echo ""
    usage
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model file not found: $MODEL"
    exit 1
fi

# Resolve absolute path
MODEL_PATH="$(realpath "$MODEL")"
MODEL_DIR="$(dirname "$MODEL_PATH")"
MODEL_NAME="$(basename "$MODEL_PATH")"

# Determine container flags based on image type
CONTAINER_FLAGS="--device=/dev/dri --security-opt seccomp=unconfined --security-opt label=disable"
ENV_FLAGS="-e AMD_VULKAN_ICD=RADV"

if [[ "$IMAGE" == *"hip"* ]] || [[ "$IMAGE" == *"rocm"* ]]; then
    CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"
    ENV_FLAGS="-e HSA_ENABLE_SDMA=0 -e GPU_MAX_HEAP_SIZE=100"
    echo "Detected HIP/ROCm image - using KFD + IPC flags"
fi

echo "=== llama.cpp Server ==="
echo "Image:   $IMAGE"
echo "Model:   $MODEL_NAME"
echo "Port:    $PORT"
echo "Context: $CTX"
echo "GPU layers: $NGL"
echo "Template: $TEMPLATE"
[ -n "$EXTRA_ARGS" ] && echo "Extra:   $EXTRA_ARGS"
echo ""
echo "Starting server at http://localhost:$PORT"
echo "Press Ctrl+C to stop"
echo ""

# Build template flag (skip if "auto")
TEMPLATE_FLAG=""
if [ "$TEMPLATE" != "auto" ]; then
    TEMPLATE_FLAG="--chat-template $TEMPLATE"
fi

exec podman run --rm -it \
    $CONTAINER_FLAGS \
    $ENV_FLAGS \
    -p "$PORT:8080" \
    -v "$MODEL_DIR:/models:ro" \
    "$IMAGE" \
    llama-server \
        --model "/models/$MODEL_NAME" \
        --host 0.0.0.0 \
        --port 8080 \
        --ctx-size "$CTX" \
        -ngl "$NGL" \
	--no-mmap \
	-fa 1 \
        $TEMPLATE_FLAG \
        $EXTRA_ARGS

