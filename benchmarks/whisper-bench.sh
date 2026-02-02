#!/bin/bash
# whisper.cpp benchmark - performance measurement
# Measures transcription speed

set -e

IMAGE="${1}"
AUDIO="${2}"
WHISPER_MODEL="${WHISPER_MODEL:-/data/models/ggml-base.en.bin}"

if [ -z "$IMAGE" ] || [ -z "$AUDIO" ]; then
    echo "Usage: $0 IMAGE_NAME AUDIO_FILE"
    echo "Example: $0 softab:whisper-hip-rocm72 /data/models/test-audio.wav"
    echo ""
    echo "Recommended test audio: 300 second sample (5 minutes)"
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

# Get audio duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO" 2>/dev/null || echo "unknown")

echo "=== whisper.cpp Benchmark ==="
echo "Image: $IMAGE"
echo "Audio: $(basename $AUDIO)"
echo "Model: $(basename $WHISPER_MODEL)"
echo "Duration: ${DURATION}s"
echo ""

# Security opts needed for ROCm memory operations
CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"
OUTPUT_FILE="whisper_bench_$(date +%Y%m%d_%H%M%S).txt"

echo "Running benchmark..."
START_TIME=$(date +%s)

podman run --rm \
    $CONTAINER_FLAGS \
    -v "$(dirname $AUDIO):/audio:ro" \
    -v "$WHISPER_MODEL:/models/ggml-base.en.bin:ro" \
    "$IMAGE" \
    whisper-cli \
        -m /models/ggml-base.en.bin \
        -f "/audio/$(basename $AUDIO)" \
        --no-timestamps \
        --print-progress 2>&1 | tee "$OUTPUT_FILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Performance:"
echo "  Audio duration: ${DURATION}s"
echo "  Processing time: ${ELAPSED}s"

if [ "$DURATION" != "unknown" ] && [ "$ELAPSED" -gt 0 ]; then
    SPEEDUP=$(echo "scale=2; $DURATION / $ELAPSED" | bc)
    echo "  Speedup: ${SPEEDUP}x realtime"
fi
