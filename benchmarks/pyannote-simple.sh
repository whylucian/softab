#!/bin/bash
# Simple pyannote test - does GPU diarization work?
# Tests if speaker diarization runs on GPU

set -e

IMAGE="${1}"
AUDIO="${2:-/data/models/test-audio.wav}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 IMAGE_NAME [AUDIO_FILE]"
    echo "Example: $0 softab:pyannote-rocm62-gfx1151 /data/models/test-audio.wav"
    exit 1
fi

if [ ! -f "$AUDIO" ]; then
    echo "ERROR: Audio file not found: $AUDIO"
    exit 1
fi

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN environment variable not set"
    echo "Get token from: https://huggingface.co/settings/tokens"
    exit 1
fi

echo "=== pyannote Simple Test ==="
echo "Image: $IMAGE"
echo "Audio: $(basename $AUDIO)"
echo ""

# Security opts needed for ROCm memory operations
CONTAINER_FLAGS="--device=/dev/kfd --device=/dev/dri --ipc=host --security-opt seccomp=unconfined --security-opt label=disable"

podman run --rm -i \
    $CONTAINER_FLAGS \
    -e HF_TOKEN="$HF_TOKEN" \
    -v "$(dirname $AUDIO):/audio:ro" \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    "$IMAGE" \
    python3 << EOF
import torch
import time
import sys

print("=== Environment Check ===")
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")

if torch.cuda.is_available():
    print(f"CUDA device: {torch.cuda.get_device_name(0)}")
    print(f"CUDA version: {torch.version.hip if hasattr(torch.version, 'hip') else 'N/A'}")
else:
    print("ERROR: GPU not available")
    sys.exit(1)

print("")
print("=== Loading pyannote Pipeline ===")

# Monkeypatch to fix use_auth_token -> token compatibility issue
import huggingface_hub
_original_hf_hub_download = huggingface_hub.hf_hub_download
def _patched_hf_hub_download(*args, **kwargs):
    if 'use_auth_token' in kwargs:
        kwargs['token'] = kwargs.pop('use_auth_token')
    return _original_hf_hub_download(*args, **kwargs)
huggingface_hub.hf_hub_download = _patched_hf_hub_download

# Also patch snapshot_download
_original_snapshot_download = huggingface_hub.snapshot_download
def _patched_snapshot_download(*args, **kwargs):
    if 'use_auth_token' in kwargs:
        kwargs['token'] = kwargs.pop('use_auth_token')
    return _original_snapshot_download(*args, **kwargs)
huggingface_hub.snapshot_download = _patched_snapshot_download

from pyannote.audio import Pipeline

# HF_TOKEN env var is automatically used by huggingface_hub
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
pipeline.to(torch.device("cuda"))

print("Pipeline loaded on GPU")
print("")

print("=== Running Diarization ===")
audio_file = "/audio/$(basename $AUDIO)"
print(f"Processing: {audio_file}")

start_time = time.time()
diarization = pipeline(audio_file)
elapsed = time.time() - start_time

print("")
print("=== Results ===")
print(f"Processing time: {elapsed:.2f}s")
print("")
print("Speaker segments:")
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f"  [{turn.start:.1f}s - {turn.end:.1f}s] {speaker}")

print("")
print("SUCCESS: Diarization completed on GPU")
EOF

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== SUCCESS: Diarization completed ==="
else
    echo ""
    echo "=== FAILED: Check output above for errors ==="
    exit 1
fi
