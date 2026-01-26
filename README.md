# SoftAb - Software Ablation Studio

**Automatically discover what works on AMD Strix Halo (gfx1151) by testing all software stack combinations.**

## The Problem

AMD Strix Halo has a **rapidly evolving software stack** with constant compatibility breakage:
- Kernel 6.18.4+ breaks standard ROCm packages (need TheRock nightlies)
- Official PyTorch wheels don't support gfx1151 (need scottt/AMD nightlies)
- Some ROCm versions fail with "invalid device function"
- Firmware 20251125 is broken, but 20260110 works
- `HSA_ENABLE_SDMA=0` required for stability, but not documented

**Manually testing every combination is dependency hell.**

## The Solution

SoftAb provides:
1. **~91 pre-configured Dockerfiles** covering all ROCm versions, backends, and configurations
2. **Automated test scripts** that systematically test what works and what fails
3. **Structured experiments** that document your specific environment (kernel, firmware) and results
4. **LLM-assisted analysis** to identify patterns across failures and successes

**Stop guessing. Test everything. Document what works.**

## Is This Project Right For You?

**✅ Use SoftAb if you want to answer:**
- Which software stacks actually work on my kernel version?
- Does ROCm 7.2 work better than 6.4.4 on Strix Halo?
- Is Vulkan RADV or AMDVLK faster for llama.cpp?
- Which GFX target (gfx1100/1150/1151/1152) should I use?
- Do environment variables like `HSA_ENABLE_SDMA` affect performance?
- What breaks when I upgrade my kernel?

**❌ Don't use SoftAb if you want to answer:**
- Which LLM is best? (Llama vs Qwen vs Phi) → Use [llm-tracker.info](https://llm-tracker.info)
- What quantization method is fastest? (Q4_K_M vs Q5_0) → Out of scope
- What batch size optimizes latency? → Out of scope
- How do different prompt lengths affect speed? → Out of scope

**SoftAb focuses on software stack configuration, not model comparisons or inference tuning.**

## Core Philosophy

**Failures are valuable data.**

When you upgrade your kernel and half your containers break, SoftAb helps you:
1. Quickly test which configurations still work
2. Document exactly what fails (error messages, stack traces)
3. Identify patterns (e.g., "all standard ROCm fails on 6.18.6, but TheRock works")
4. Build a compatibility matrix for your specific environment

This isn't just about finding the fastest config - it's about **navigating dependency hell systematically** instead of trial-and-error.

## Methodology

SoftAb uses a principled experimental approach:

1. **Record your environment** (kernel, firmware, distro) - the non-mutable baseline
2. **Build multiple Docker images** with different software stacks (ROCm versions, backends, GFX targets)
3. **Run simple tests on ALL images** - many will fail, that's expected and valuable
4. **Run performance benchmarks** ONLY on configurations that work
5. **Analyze with LLM** to identify patterns ("all Fedora ROCm fails on kernel 6.18.6+")
6. **Document the compatibility matrix** for your environment

**Key insight**: You don't know what works until you test it. Automated testing beats manual trial-and-error.

## Typical Workflow: Testing After a Kernel Upgrade

Example: You just upgraded to kernel 6.18.6 and want to know what still works.

```bash
# 1. Create experiment directory
cp -r experiments/TEMPLATE experiments/2026-01-26_kernel-6.18.6-test
cd experiments/2026-01-26_kernel-6.18.6-test

# 2. Record environment (captures kernel version, firmware, etc.)
./record-environment.sh > ENVIRONMENT.txt

# 3. Edit run-all-benchmarks.sh to test a matrix of configs
# Test everything: Vulkan, ROCm 6.4.4, ROCm 7.2, TheRock nightlies

# 4. Run tests - many will fail, that's the point
./run-all-benchmarks.sh

# Results:
# - Vulkan configs: ✅ All work (Vulkan doesn't care about kernel)
# - Standard ROCm 6.4.4/7.2: ❌ Fail with "invalid device function"
# - TheRock nightlies: ✅ Work (built for newer kernels)
# - PyTorch Fedora repos: ❌ Fail to compile

# 5. Ask LLM to analyze raw_results/*.log
# "Which configurations work on kernel 6.18.6? What are the error patterns?"

# 6. Document in FINDINGS.md:
# "Kernel 6.18.6 breaks all standard ROCm. Use TheRock nightlies or Vulkan."
```

**Value**: You now have a compatibility matrix for kernel 6.18.6 that helps you and the community.

## Ablation Variables

| Variable | Options |
|----------|---------|
| **GFX target** | gfx1100, gfx1150, gfx1151, gfx1152 |
| **Driver** | AMDVLK, RADV |
| **ROCm version** | 6.4.4, 7.0, 7.1.1, 7.2, TheRock nightlies |
| **ROCm source** | Fedora repos, AMD repos, TheRock pip |
| **Backend** | Vulkan, ROCm HIP, HIP+rocWMMA |
| **Python version** | 3.11, 3.12 |
| **Environment vars** | SDMA, hipBLASLt, allocator configs |
| **Flash Attention** | Enabled, Disabled |

## Workloads

We test four representative workloads:

- **PyTorch** - Matrix multiplication (GEMM) benchmark
- **llama.cpp** - LLM inference (prompt processing + token generation)
- **whisper.cpp** - Speech recognition (transcription speed)
- **pyannote** - Speaker diarization (GPU acceleration)

One representative model per workload for simple tests. Extended benchmarks use multiple model sizes.

## Quick Start

**New users**: See [QUICKSTART.md](QUICKSTART.md) for a 5-minute system test and 15-minute experiment walkthrough.

**Experienced users**:

```bash
# 1. Create experiment
cp -r experiments/TEMPLATE experiments/$(date +%Y-%m-%d)_test
cd experiments/$(date +%Y-%m-%d)_test
./record-environment.sh > ENVIRONMENT.txt

# 2. Build images
cd /home/tc/softab
./docker/build-matrix.sh build-llama

# 3. Run benchmarks
cd experiments/$(date +%Y-%m-%d)_test
./run-all-benchmarks.sh

# 4. Analyze results (use LLM on raw_results/)
```

## Project Structure

```
softab/
├── README.md                  # This file
├── QUICKSTART.md              # 5-minute getting started guide
├── KNOWLEDGE_BASE.md          # Community knowledge index
├── QUICK_REFERENCE.md         # Command cheatsheet
├── verify-strix-halo.sh       # System verification
│
├── docs/                      # Detailed documentation
│   ├── hardware-specs.md      # Strix Halo specifications
│   ├── rocm-support.md        # ROCm compatibility
│   ├── applications.md        # Software support status
│   ├── troubleshooting.md     # Known issues & fixes
│   └── community-resources.md # Community links & glossary
│
├── docker/                    # Container images (~91 Dockerfiles)
│   ├── build-matrix.sh        # Canonical image builder
│   ├── base/                  # Base images
│   ├── rocm/                  # ROCm variants
│   ├── pytorch/               # PyTorch configs
│   ├── llama-cpp/             # llama.cpp backends
│   ├── whisper-cpp/           # whisper.cpp backends
│   ├── pyannote/              # pyannote configs
│   ├── vllm/                  # vLLM configs
│   └── toolbox/               # Fedora Toolbox environments
│
├── benchmarks/                # Workload benchmarks
│   ├── *-simple.sh            # Does it work? (phase 1)
│   └── *-bench.sh             # How well? (phase 2)
│
├── experiments/               # Experiment framework
│   ├── README.md              # Methodology guide
│   ├── TEMPLATE/              # New experiment template
│   └── YYYY-MM-DD_name/       # Your experiments
│
├── scripts/                   # Ablation tools
│   ├── ablation-*.sh          # Specific ablation tests
│   └── download-models.sh     # Model downloader
│
├── tests/                     # Legacy test suite
└── samples/                   # Test data
```

## Benchmark Types

### Simple Tests (Does it work?)

Run FIRST to identify working configurations:

```bash
benchmarks/pytorch-simple.sh IMAGE_NAME
benchmarks/llama-simple.sh IMAGE_NAME MODEL_PATH
benchmarks/whisper-simple.sh IMAGE_NAME AUDIO_PATH
```

### Performance Tests (How well does it work?)

Run SECOND on working configurations:

```bash
benchmarks/pytorch-gemm.sh IMAGE_NAME [MATRIX_SIZE] [ITERATIONS]
benchmarks/llama-bench.sh IMAGE_NAME MODEL_PATH
benchmarks/whisper-bench.sh IMAGE_NAME AUDIO_PATH
```

### Extended Tests (Deep analysis)

Run THIRD on promising configurations:

- Multiple model sizes
- Multiple context lengths
- Long-running stress tests
- Memory bandwidth profiling

See `scripts/` for extended benchmark scripts.

## Example Workflow

### Testing ROCm Versions

```bash
# 1. Create experiment
cp -r experiments/TEMPLATE experiments/2026-01-26_rocm-versions
cd experiments/2026-01-26_rocm-versions

# 2. Record environment
./record-environment.sh > ENVIRONMENT.txt

# 3. Build images (from project root)
cd /home/tc/softab
podman build -t softab:llama-hip-rocm644 -f docker/llama-cpp/Dockerfile.hip-rocm644 .
podman build -t softab:llama-hip-rocm711 -f docker/llama-cpp/Dockerfile.hip-rocm711 .
podman build -t softab:llama-hip-rocm72 -f docker/llama-cpp/Dockerfile.hip-rocm72 .

# 4. Edit run-all-benchmarks.sh to specify these images
cd experiments/2026-01-26_rocm-versions
nano run-all-benchmarks.sh
# Add to IMAGES array:
#   "softab:llama-hip-rocm644"
#   "softab:llama-hip-rocm711"
#   "softab:llama-hip-rocm72"

# 5. Run benchmarks
./run-all-benchmarks.sh

# 6. Analyze results
# Review raw_results/*.log
# Use Claude to summarize findings
# Document in FINDINGS.md
```

## Hardware Target

- **APU**: AMD Ryzen AI Max+ 395 (Strix Halo)
- **GPU**: Radeon 8060S (40 CU, gfx1151)
- **Architecture**: RDNA 3.5 / Zen 5
- **Memory**: 128GB unified LPDDR5X-8000 (256 GB/s GPU bandwidth)
- **Peak FP16**: 59.4 TFLOPS theoretical

## Key Resources

- [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) - Community findings, optimal configs, known issues
- [experiments/README.md](experiments/README.md) - Detailed experiment methodology
- [strixhalo.wiki](https://strixhalo.wiki) - Comprehensive setup guides
- [lhl/strix-halo-testing](https://github.com/lhl/strix-halo-testing) - Community benchmarks
- [kyuz0 toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) - Pre-built containers

## Design Principles

1. **Failures are Data**: Most configs will fail on any given kernel/firmware combination. Document what fails and why - it's as valuable as knowing what works.
2. **Test Everything, Automatically**: Don't guess which ROCm version works. Build Docker images for all combinations and test systematically.
3. **Reproducibility**: Document all variables, especially non-mutable ones (kernel, firmware, distro)
4. **Separation of Concerns**: Images ≠ benchmarks. Build once, test many times.
5. **Systematic Testing**: Test simple → performance → extended
6. **LLM-Assisted Analysis**: Use AI to find patterns in failures and successes
7. **Version Control**: Commit environment and findings, not raw logs

## Version Control Policy

### What to Commit

**✅ Always commit:**
- Dockerfiles and build configurations
- Benchmark scripts (`benchmarks/`, `scripts/`)
- Experiment templates (`experiments/TEMPLATE/`)
- Per-experiment metadata:
  - `ENVIRONMENT.txt` - System configuration snapshot
  - `FINDINGS.md` - LLM-analyzed summary and conclusions
  - `README.md` - What you tested and why
- Documentation (`docs/`, `*.md`)
- System verification scripts

**❌ Never commit:**
- Raw benchmark logs (`experiments/*/raw_results/*.log`)
- Large result files (`results/`)
- Models and audio files (`*.gguf`, `*.wav`, `models/`, `/data/`)
- Build artifacts (`*.o`, `*.so`)
- Python bytecode (`__pycache__/`, `*.pyc`)
- Virtual environments (`.venv*/`)
- Editor/IDE configs (`.vscode/`, `.idea/`)

### Why This Policy?

**Raw logs are too large**: A single experiment run can generate 100+ MB of logs. Instead:
- Commit the _analysis_ (FINDINGS.md with key metrics and conclusions)
- Commit the _methodology_ (what you tested and how)
- Anyone can reproduce your results by re-running the experiment

**Models are downloaded separately**: Models can be 10-100 GB. Use `scripts/download-models.sh` or document download instructions instead.

**Example experiment commit**:
```
experiments/2026-01-26_rocm-version-comparison/
├── ENVIRONMENT.txt          # ✅ Commit (kernel, firmware, etc.)
├── FINDINGS.md              # ✅ Commit (LLM analysis, conclusions)
├── README.md                # ✅ Commit (what you tested)
├── run-all-benchmarks.sh    # ✅ Commit (methodology)
└── raw_results/             # ❌ Ignored by git (too large)
    ├── image1_bench.log     # Analyze → summarize in FINDINGS.md
    └── image2_bench.log
```

### Git Configuration

The `.gitignore` file already handles this policy. If you accidentally committed large files:

```bash
# Remove large files from git history
git rm --cached models/*.gguf
git rm --cached experiments/*/raw_results/*.log

# Commit the removal
git commit -m "Remove accidentally committed large files"
```

## License

MIT
