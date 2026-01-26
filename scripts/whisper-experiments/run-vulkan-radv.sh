#!/bin/bash
# Run whisper.cpp with Vulkan RADV backend
MODEL="${1:-/models/ggml-large-v3.bin}"
AUDIO="${2:-/workspace/test_audio.wav}"

podman run --rm \
    --device=/dev/dri --security-opt label=disable \
    -v /data/models/whisper:/models:ro \
    -v /home/tc/softab/samples:/workspace:ro \
    softab:whisper-vulkan-radv \
    whisper-cli -m "$MODEL" -f "$AUDIO"
