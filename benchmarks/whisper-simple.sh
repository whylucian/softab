#!/bin/bash
# Simple whisper.cpp test - does it work?
# Tests if audio file is transcribed

set -e

IMAGE="${1}"
AUDIO="${2:-/data/models/test-audio.wav}"
WHISPER_MODEL="${WHISPER_MODEL:-/data/models/ggml-base.en.bin}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 IMAGE_NAME [AUDIO_FILE]"
    echo "Example: $0 softab:whisper-hip-rocm72 /data/models/test-audio.wav"
    exit 1
fi

if [ ! -f "$AUDIO" ]; then
    echo "ERROR: Audio file not found: $AUDIO"
    exit 1
fi

if [ ! -f "$WHISPER_MODEL" ]; then
    echo "ERROR: Whisper model not found: $WHISPER_MODEL"
    echo "Download with: huggingface-cli download ggerganov/whisper.cpp ggml-base.en.bin --local-dir /data/models"
    exit 1
fi

echo "=== whisper.cpp Simple Test ==="
echo "Image: $IMAGE"
echo "Audio: $(basename $AUDIO)"
echo "Model: $(basename $WHISPER_MODEL)"
echo ""

# HIP/ROCm requires --ipc=host on Strix Halo
# Security opts needed for ROCm memory operations
CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"

podman run --rm \
    $CONTAINER_FLAGS \
    -v "$(dirname $AUDIO):/audio:ro" \
    -v "$WHISPER_MODEL:/models/ggml-base.en.bin:ro" \
    "$IMAGE" \
    whisper-cli \
        -m /models/ggml-base.en.bin \
        -f "/audio/$(basename $AUDIO)" \
        --print-colors \
        --no-timestamps 2>&1 | tee /tmp/whisper-simple-test.log

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== SUCCESS: Audio transcribed ==="
else
    echo ""
    echo "=== FAILED: Check output above for errors ==="
    exit 1
fi
