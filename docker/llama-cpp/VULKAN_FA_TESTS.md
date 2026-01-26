# Vulkan Flash Attention Tests

**Created:** 2026-01-25  
**Purpose:** Test if Flash Attention improves our best LLM performer (Vulkan RADV: 5369 t/s)

## Background

Our best llama.cpp performer is **Vulkan RADV at 5369 t/s**, but the benchmark didn't include the `-fa 1` (Flash Attention) flag.

Our ROCm HIP test showed **Flash Attention provides +12.5% improvement**.

**Question:** Can we push Vulkan performance even higher with Flash Attention?

## Test Images Created

### 1. Vulkan RADV + Flash Attention
**Dockerfile:** `Dockerfile.vulkan-radv-fa`  
**Image:** `softab:llama-vulkan-radv-fa`

**Changes from baseline:**
- Added `-fa 1` flag to benchmarks
- All other settings identical to original winner

**Expected result:** ~6040 t/s (5369 × 1.125)

**Build:**
```bash
podman build --security-opt label=disable \
  -f docker/llama-cpp/Dockerfile.vulkan-radv-fa \
  -t softab:llama-vulkan-radv-fa .
```

**Test:**
```bash
podman run --rm --device=/dev/dri \
  -v ~/models:/models:ro \
  softab:llama-vulkan-radv-fa \
  run-bench /models/llama3.2-3b-q8.gguf
```

---

### 2. Vulkan RADV + FA + HSA Fine Grain
**Dockerfile:** `Dockerfile.vulkan-radv-fa-finegrain`  
**Image:** `softab:llama-vulkan-radv-fa-finegrain`

**Changes from baseline:**
- Added `-fa 1` flag
- Added `HSA_FORCE_FINE_GRAIN_PCIE=1` environment variable

**Rationale:** 
APU unified memory might benefit from fine-grained memory allocation instead of coarse-grained. This is typically a HIP/ROCm setting but may affect Vulkan behavior on APU systems.

**Expected result:** Similar or slightly better than FA-only test

**Build:**
```bash
podman build --security-opt label=disable \
  -f docker/llama-cpp/Dockerfile.vulkan-radv-fa-finegrain \
  -t softab:llama-vulkan-radv-fa-finegrain .
```

**Test:**
```bash
podman run --rm --device=/dev/dri \
  -v ~/models:/models:ro \
  softab:llama-vulkan-radv-fa-finegrain \
  run-bench /models/llama3.2-3b-q8.gguf
```

---

## Comparison Matrix

| Configuration | FA Flag | HSA Fine Grain | Expected pp512 (t/s) |
|---------------|---------|----------------|----------------------|
| Original baseline | ❌ No | ❌ No | 5369 (measured) |
| + Flash Attention | ✅ Yes | ❌ No | ~6040 (projected) |
| + FA + Fine Grain | ✅ Yes | ✅ Yes | ~6040-6200 (?) |

---

## Build Instructions

### Build both images:
```bash
# Image 1: Vulkan + FA
podman build --security-opt label=disable \
  -f docker/llama-cpp/Dockerfile.vulkan-radv-fa \
  -t softab:llama-vulkan-radv-fa .

# Image 2: Vulkan + FA + Fine Grain
podman build --security-opt label=disable \
  -f docker/llama-cpp/Dockerfile.vulkan-radv-fa-finegrain \
  -t softab:llama-vulkan-radv-fa-finegrain .
```

### Run benchmarks (after GPU is free):
```bash
MODEL="/home/tc/models/llama3.2-3b-q8.gguf"

echo "=== Test 1: Vulkan + FA ==="
podman run --rm --device=/dev/dri -v ~/models:/models:ro \
  softab:llama-vulkan-radv-fa run-bench "$MODEL"

echo ""
echo "=== Test 2: Vulkan + FA + Fine Grain ==="
podman run --rm --device=/dev/dri -v ~/models:/models:ro \
  softab:llama-vulkan-radv-fa-finegrain run-bench "$MODEL"
```

---

## Expected Outcomes

### Scenario 1: FA helps (+12.5% like ROCm HIP)
- Vulkan + FA: **~6040 t/s** 🚀 NEW CHAMPION
- Confirms FA works across both backends

### Scenario 2: FA helps less on Vulkan
- Vulkan + FA: **~5700-5900 t/s** 
- Still an improvement, but smaller gain

### Scenario 3: No improvement
- Vulkan + FA: **~5369 t/s** (same)
- Vulkan may already optimize attention differently

### Fine Grain Impact:
- Likely minimal on Vulkan (HSA is primarily ROCm/HIP)
- May see 0-5% difference
- Worth testing for completeness

---

## Next Steps After Testing

1. Record results in `results/vulkan-fa-tests-20260125/`
2. Update FINDINGS.md with new champion (if applicable)
3. Update KNOWLEDGE_BASE.md with Flash Attention Vulkan findings
4. Update all benchmark scripts to include `-fa 1` by default

---

**Status:** Dockerfiles created, ready to build when GPU is available
