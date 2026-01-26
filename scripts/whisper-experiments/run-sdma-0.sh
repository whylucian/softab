#!/bin/bash
# Run whisper.cpp with SDMA disabled (HSA_ENABLE_SDMA=0)
MODEL="${1:-/models/ggml-large-v3.bin}"
AUDIO="${2:-/workspace/test_audio.wav}"

podman run --rm \
    --device=/dev/kfd --device=/dev/dri --ipc=host --security-opt label=disable \
    -v /data/models/whisper:/models:ro \
    -v /home/tc/softab/samples:/workspace:ro \
    softab:whisper-ablation-sdma-0 \
    whisper-cli -m "$MODEL" -f "$AUDIO"
