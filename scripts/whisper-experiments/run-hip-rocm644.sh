#!/bin/bash
# Run whisper.cpp with HIP ROCm 6.4.4 (expected to fail on gfx1151)
MODEL="${1:-/models/ggml-large-v3.bin}"
AUDIO="${2:-/workspace/test_audio.wav}"

podman run --rm \
    --device=/dev/kfd --device=/dev/dri --ipc=host --security-opt label=disable \
    -v /data/models/whisper:/models:ro \
    -v /home/tc/softab/samples:/workspace:ro \
    softab:whisper-hip-rocm644-gfx1151 \
    whisper-cli -m "$MODEL" -f "$AUDIO"
