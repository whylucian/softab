#!/bin/bash
# Simple whisper.cpp test - does it work?
# Tests if audio file is transcribed

set -e

IMAGE="${1}"
AUDIO="${2:-/home/tc/softab/samples/jfk.wav}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 IMAGE_NAME [AUDIO_FILE]"
    echo "Example: $0 softab:whisper-hip-rocm72 samples/jfk.wav"
    exit 1
fi

if [ ! -f "$AUDIO" ]; then
    echo "WARNING: Audio file not found: $AUDIO"
    echo "Using default audio if available in container"
fi

echo "=== whisper.cpp Simple Test ==="
echo "Image: $IMAGE"
echo "Audio: $(basename $AUDIO)"
echo ""

# HIP/ROCm requires --ipc=host on Strix Halo
CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host"

if [ -f "$AUDIO" ]; then
    podman run --rm \
        $CONTAINER_FLAGS \
        -v "$(dirname $AUDIO):/audio:ro" \
        "$IMAGE" \
        whisper-cli \
            -m /whisper.cpp/models/ggml-base.en.bin \
            -f "/audio/$(basename $AUDIO)" \
            --print-colors \
            --no-timestamps 2>&1 | tee /tmp/whisper-simple-test.log
else
    echo "No audio file mounted, testing with container's sample if available"
    podman run --rm $CONTAINER_FLAGS "$IMAGE" \
        whisper-cli -m /whisper.cpp/models/ggml-base.en.bin -f /whisper.cpp/samples/jfk.wav --no-timestamps
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "=== SUCCESS: Audio transcribed ==="
else
    echo ""
    echo "=== FAILED: Check output above for errors ==="
    exit 1
fi
