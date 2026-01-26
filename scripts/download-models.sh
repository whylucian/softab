#!/bin/bash
# Download GGUF models for comprehensive benchmarking
# Models are stored in /data/models/gguf/ (override with MODELS_DIR env var)

set -e

MODELS_DIR="${MODELS_DIR:-/data/models/gguf}"
mkdir -p "$MODELS_DIR"

echo "=== GGUF Model Downloader ==="
echo "Download directory: $MODELS_DIR"
echo ""

# Check for huggingface-cli
if ! command -v huggingface-cli &> /dev/null; then
    echo "Installing huggingface-hub..."
    pip install -q huggingface-hub
fi

# Model definitions: SIZE|REPO|FILENAME
# Using correct HuggingFace repo names
MODELS=(
    # ~1B - TinyLlama from TheBloke
    "1B|TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF|tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"

    # ~3B - Llama 3.2 3B from bartowski
    "3B|bartowski/Llama-3.2-3B-Instruct-GGUF|Llama-3.2-3B-Instruct-Q4_K_M.gguf"

    # ~7B - Qwen 2.5 7B from Qwen official
    "7B|Qwen/Qwen2.5-7B-Instruct-GGUF|qwen2.5-7b-instruct-q4_k_m.gguf"

    # ~14B - Qwen 2.5 14B
    "14B|Qwen/Qwen2.5-14B-Instruct-GGUF|qwen2.5-14b-instruct-q4_k_m.gguf"

    # ~32B - Qwen 2.5 32B
    "32B|Qwen/Qwen2.5-32B-Instruct-GGUF|qwen2.5-32b-instruct-q4_k_m.gguf"

    # ~70B - Llama 3.1 70B from bartowski
    "70B|bartowski/Meta-Llama-3.1-70B-Instruct-GGUF|Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf"
)

download_model() {
    local SIZE="$1"
    local REPO="$2"
    local FILENAME="$3"
    local TARGET="$MODELS_DIR/$FILENAME"

    if [ -f "$TARGET" ]; then
        echo "[$SIZE] Already exists: $FILENAME"
        return 0
    fi

    echo "[$SIZE] Downloading: $FILENAME"
    echo "       From: $REPO"

    # Try download
    if huggingface-cli download "$REPO" "$FILENAME" --local-dir "$MODELS_DIR" --local-dir-use-symlinks False 2>/dev/null; then
        echo "       Done: $(du -h "$TARGET" 2>/dev/null | cut -f1)"
    else
        echo "       FAILED - trying alternate method..."
        # Try direct URL download as fallback
        local URL="https://huggingface.co/${REPO}/resolve/main/${FILENAME}"
        if curl -L -o "$TARGET" "$URL" 2>/dev/null; then
            echo "       Done via curl: $(du -h "$TARGET" | cut -f1)"
        else
            echo "       FAILED to download $FILENAME"
            return 1
        fi
    fi
}

# Parse command line
SIZES_TO_DOWNLOAD="${1:-all}"

echo "Sizes to download: $SIZES_TO_DOWNLOAD"
echo ""

for MODEL_DEF in "${MODELS[@]}"; do
    IFS='|' read -r SIZE REPO FILENAME <<< "$MODEL_DEF"

    if [ "$SIZES_TO_DOWNLOAD" = "all" ] || [[ "$SIZES_TO_DOWNLOAD" == *"$SIZE"* ]]; then
        download_model "$SIZE" "$REPO" "$FILENAME" || true
    fi
done

echo ""
echo "=== Download Complete ==="
echo "Models in: $MODELS_DIR"
ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null || echo "No models downloaded yet"

echo ""
echo "Disk usage:"
du -sh "$MODELS_DIR"
