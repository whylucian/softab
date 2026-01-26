# whisper.cpp with ROCm HIP backend
# 58x speedup over CPU documented on Strix Halo

FROM docker.io/rocm/dev-ubuntu-24.04:6.4.3-complete

LABEL maintainer="softab"
LABEL description="whisper.cpp ROCm HIP build for Strix Halo ablation"
LABEL backend="hip"

ARG GFX_TARGET=gfx1151

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install build tools + ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git \
    ffmpeg \
    bc jq htop \
    && rm -rf /var/lib/apt/lists/*

# Environment
ENV PATH="/opt/rocm/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
ENV ROCM_PATH="/opt/rocm"
ENV HIP_PATH="/opt/rocm"
ENV CMAKE_PREFIX_PATH="/opt/rocm"

# Critical Strix Halo settings
ENV HSA_ENABLE_SDMA=0
ENV HIP_VISIBLE_DEVICES=0

# GFX target
ENV GPU_TARGETS=${GFX_TARGET}
ENV AMDGPU_TARGETS=${GFX_TARGET}

# Clone whisper.cpp
RUN git clone --depth 1 https://github.com/ggerganov/whisper.cpp /whisper.cpp

WORKDIR /whisper.cpp

# Download base model for testing
RUN bash ./models/download-ggml-model.sh base.en

# Build with HIP
RUN cmake -B build-hip \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS="${GFX_TARGET}" \
    -DCMAKE_BUILD_TYPE=Release \
    -G Ninja && \
    cmake --build build-hip --parallel $(nproc)

# Create symlinks
RUN ln -s /whisper.cpp/build-hip/bin/whisper-cli /usr/local/bin/whisper-cli && \
    ln -s /whisper.cpp/build-hip/bin/whisper-bench /usr/local/bin/whisper-bench 2>/dev/null || true

# User setup
RUN useradd -m -s /bin/bash runner && \
    usermod -a -G video,render runner

WORKDIR /workspace

# Benchmark script
RUN echo '#!/bin/bash\n\
AUDIO=${1:-/whisper.cpp/samples/jfk.wav}\n\
MODEL=${2:-/whisper.cpp/models/ggml-base.en.bin}\n\
echo "=== whisper.cpp HIP Benchmark ==="\n\
echo "GFX Target: ${GPU_TARGETS}"\n\
rocminfo 2>/dev/null | grep -A1 "Marketing Name" | head -2\n\
echo ""\n\
echo "Audio: $AUDIO"\n\
echo "Model: $MODEL"\n\
echo ""\n\
if [ -f "$AUDIO" ] && [ -f "$MODEL" ]; then\n\
    time whisper-cli -m "$MODEL" -f "$AUDIO"\n\
else\n\
    echo "Files not found"\n\
    echo "Usage: run-bench <audio.wav> [model.bin]"\n\
fi\n\
' > /usr/local/bin/run-bench && chmod +x /usr/local/bin/run-bench

# Labels for ablation tracking
LABEL gfx.target="${GFX_TARGET}"
LABEL ablation.type="whisper-cpp"
LABEL ablation.backend="hip"
LABEL base.image="rocm/dev-ubuntu-24.04:6.4.3-complete"

CMD ["whisper-cli", "--help"]
