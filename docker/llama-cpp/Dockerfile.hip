# llama.cpp with ROCm HIP backend
# Using Ubuntu ROCm base for proper AMD layout

FROM docker.io/rocm/dev-ubuntu-24.04:6.4.3-complete

LABEL maintainer="softab"
LABEL description="llama.cpp ROCm HIP build for Strix Halo ablation"
LABEL backend="hip"

ARG GFX_TARGET=gfx1151
ARG USE_HIPBLASLT=1

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git \
    bc jq htop \
    && rm -rf /var/lib/apt/lists/*

# Environment (already set in base image, reinforce)
ENV PATH="/opt/rocm/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
ENV ROCM_PATH="/opt/rocm"
ENV HIP_PATH="/opt/rocm"
ENV CMAKE_PREFIX_PATH="/opt/rocm"

# Critical Strix Halo settings
ENV HSA_ENABLE_SDMA=0
ENV ROCBLAS_USE_HIPBLASLT=${USE_HIPBLASLT}
ENV HIP_VISIBLE_DEVICES=0

# GFX target
ENV GPU_TARGETS=${GFX_TARGET}
ENV AMDGPU_TARGETS=${GFX_TARGET}

# Clone llama.cpp
RUN git clone --depth 1 https://github.com/ggerganov/llama.cpp /llama.cpp

WORKDIR /llama.cpp

# Build with HIP
RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -B build-hip \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS="${GFX_TARGET}" \
    -DGGML_HIP_UMA=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -G Ninja && \
    cmake --build build-hip --parallel $(nproc)

# Create symlinks
RUN ln -s /llama.cpp/build-hip/bin/llama-cli /usr/local/bin/llama-cli && \
    ln -s /llama.cpp/build-hip/bin/llama-bench /usr/local/bin/llama-bench && \
    ln -s /llama.cpp/build-hip/bin/llama-server /usr/local/bin/llama-server

# User setup
RUN useradd -m -s /bin/bash runner && \
    usermod -a -G video,render runner

# UMA memory for large models
ENV GGML_CUDA_ENABLE_UNIFIED_MEMORY=ON

WORKDIR /workspace

# Benchmark script
RUN echo '#!/bin/bash\n\
MODEL=${1:-/models/test.gguf}\n\
echo "=== llama.cpp HIP Benchmark ==="\n\
echo "GFX Target: ${GPU_TARGETS}"\n\
echo "hipBLASLt: ${ROCBLAS_USE_HIPBLASLT}"\n\
rocminfo 2>/dev/null | grep -A1 "Marketing Name" | head -2\n\
echo ""\n\
if [ -f "$MODEL" ]; then\n\
    llama-bench --mmap 0 -ngl 999 -m "$MODEL" -p 512,1024,2048 -n 32\n\
else\n\
    echo "Model not found: $MODEL"\n\
    echo "Mount models with: -v /path/to/models:/models"\n\
fi\n\
' > /usr/local/bin/run-bench && chmod +x /usr/local/bin/run-bench

# Labels for ablation tracking
LABEL gfx.target="${GFX_TARGET}"
LABEL hipblaslt="${USE_HIPBLASLT}"
LABEL ablation.type="llama-cpp"
LABEL ablation.backend="hip"
LABEL base.image="rocm/dev-ubuntu-24.04:6.4.3-complete"

CMD ["llama-cli", "--help"]
