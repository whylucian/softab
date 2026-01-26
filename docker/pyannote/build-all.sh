#!/bin/bash
# Build all pyannote-audio experimental images for gfx1151

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GFX_TARGET="${GFX_TARGET:-gfx1151}"

echo "=== Building pyannote-audio Experimental Images ==="
echo "GFX Target: $GFX_TARGET"
echo "Working directory: $SCRIPT_DIR"
echo ""

# Array of images to build: dockerfile:tag
IMAGES=(
    # ROCm 7.2 (Native gfx1151 support)
    "Dockerfile.rocm72-py310:pyannote-rocm72-py310-gfx1151"
    "Dockerfile.rocm72-py311-community1:pyannote-rocm72-py311-community1-gfx1151"
    "Dockerfile.rocm72-py311-v340:pyannote-rocm72-py311-v340-gfx1151"

    # ROCm 6.4.4 (Stable stepping stone)
    "Dockerfile.rocm644-py310:pyannote-rocm644-py310-gfx1151"

    # scottt/TheRock wheels
    "Dockerfile.therock-py311:pyannote-therock-py311-gfx1151"

    # WhisperX (Combined transcription + diarization)
    "Dockerfile.whisperx-rocm72:whisperx-rocm72-gfx1151"
)

# Build each image
for spec in "${IMAGES[@]}"; do
    IFS=':' read -r dockerfile tag <<< "$spec"

    echo ""
    echo "========================================="
    echo "Building: $tag"
    echo "Dockerfile: $dockerfile"
    echo "========================================="

    podman build \
        -f "$SCRIPT_DIR/$dockerfile" \
        -t "softab:$tag" \
        --build-arg GFX_TARGET="$GFX_TARGET" \
        "$SCRIPT_DIR/../.." || {
        echo "ERROR: Failed to build $tag"
        exit 1
    }

    echo "✓ Built: softab:$tag"
done

echo ""
echo "=== Build Summary ==="
echo "Successfully built ${#IMAGES[@]} images:"
for spec in "${IMAGES[@]}"; do
    IFS=':' read -r dockerfile tag <<< "$spec"
    echo "  - softab:$tag"
done

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Get HuggingFace token:"
echo "   https://huggingface.co/settings/tokens"
echo ""
echo "2. Accept model conditions:"
echo "   https://huggingface.co/pyannote/speaker-diarization-community-1"
echo "   https://huggingface.co/pyannote/segmentation-3.0"
echo ""
echo "3. Test an image:"
echo "   export HF_TOKEN=hf_your_token_here"
echo "   podman run --rm --device=/dev/kfd --device=/dev/dri --ipc=host \\"
echo "     -e HF_TOKEN=\$HF_TOKEN \\"
echo "     softab:pyannote-rocm72-py311-community1-gfx1151 \\"
echo "     python test_diarization.py"
echo ""
echo "4. Run benchmark:"
echo "   podman run --rm --device=/dev/kfd --device=/dev/dri --ipc=host \\"
echo "     -e HF_TOKEN=\$HF_TOKEN \\"
echo "     -v ~/samples:/samples:ro \\"
echo "     softab:pyannote-rocm72-py311-community1-gfx1151 \\"
echo "     python bench_diarization.py /samples/audio.wav"
echo ""
