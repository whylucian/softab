#!/bin/bash
# Run whisper.cpp with HIP ROCm 7.2 (default configuration)
MODEL="${1:-/models/ggml-large-v3.bin}"
AUDIO="${2:-/workspace/test_audio.wav}"

podman run --rm \
    --device=/dev/kfd --device=/dev/dri --ipc=host --security-opt label=disable \
    -v /data/models/whisper:/models:ro \
    -v /home/tc/softab/samples:/workspace:ro \
    softab:whisper-hip-rocm72-gfx1151 \
    whisper-cli -m "$MODEL" -f "$AUDIO"
