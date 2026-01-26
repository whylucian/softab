#!/bin/bash
# Build fixed pyannote images with proper ROCm PyTorch

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="./results/pyannote-builds-${TIMESTAMP}"
mkdir -p "$LOG_DIR"

echo "========================================="
echo "Building pyannote-audio ROCm Images"
echo "========================================="
echo "Timestamp: $TIMESTAMP"
echo "Logs: $LOG_DIR"
echo ""

# Image 1: AMD Official with torchaudio fix
echo "1. Building AMD Official ROCm 6.1..."
podman build \
  --security-opt=label=disable \
  -f docker/pyannote/Dockerfile.amd-rocm61-fixed \
  -t softab:pyannote-amd-rocm61-gfx1151 \
  --build-arg GFX_TARGET=gfx1151 \
  . 2>&1 | tee "$LOG_DIR/amd-rocm61.log"

if [ $? -eq 0 ]; then
    echo "✓ AMD Official built successfully"
else
    echo "✗ AMD Official build failed"
fi

echo ""
echo "========================================="
echo "Build Summary"
echo "========================================="
echo "Logs saved to: $LOG_DIR/"
echo ""
podman images | grep pyannote | head -5
