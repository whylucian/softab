# SoftAb Experiments

This directory contains organized experiment runs. Each experiment tests a specific set of variables while keeping the system environment constant.

**Core principle**: Test everything systematically. Failures are valuable data - they tell you what's incompatible with your kernel/firmware/distro combination.

## Structure

```
experiments/
├── README.md                    # This file
├── TEMPLATE/                    # Template for new experiments
│   ├── README.md                # Experiment documentation template
│   ├── record-environment.sh    # Record non-mutable system variables
│   ├── run-all-benchmarks.sh    # Master runner for all benchmarks
│   └── raw_results/             # Created when benchmarks run
└── YYYY-MM-DD_description/      # Your experiment runs
    ├── ENVIRONMENT.txt          # Recorded system state
    ├── README.md                # What variables you're testing
    ├── run-all-benchmarks.sh    # Modified from template
    ├── raw_results/             # Raw benchmark outputs
    └── FINDINGS.md              # LLM-analyzed summary
```

## Creating a New Experiment

1. **Copy the template:**
   ```bash
   cp -r experiments/TEMPLATE experiments/$(date +%Y-%m-%d)_my-experiment
   cd experiments/$(date +%Y-%m-%d)_my-experiment
   ```

2. **Record environment (non-mutable variables):**
   ```bash
   ./record-environment.sh > ENVIRONMENT.txt
   ```

3. **Edit run-all-benchmarks.sh:**
   - Update the `IMAGES` array with images to test
   - Specify model/audio file paths if needed

4. **Run benchmarks:**
   ```bash
   ./run-all-benchmarks.sh
   ```
   This will create `raw_results/` with all test outputs.

5. **Analyze results:**
   - Use Claude/LLM to analyze raw_results/*.log files
   - Document key findings in FINDINGS.md

## Non-Mutable Variables

These MUST remain constant within a single experiment:

- Kernel version and parameters
- Linux distribution and version
- Firmware version
- Hardware (CPU, GPU, Memory)
- Memory configuration (GART/GTT settings)
- Date/time of run

Record these with `record-environment.sh` before starting.

## Mutable Variables (What We Test)

Each experiment should vary ONE or more of:

- ROCm version (6.4.4, 7.0, 7.1.1, 7.2)
- Backend (Vulkan vs HIP)
- Vulkan driver (RADV vs AMDVLK)
- GFX target (gfx1100, gfx1150, gfx1151, gfx1152)
- Python version (3.11 vs 3.12)
- Environment variables (SDMA, hipBLASLt, etc.)
- Flash Attention (enabled vs disabled)
- Container runtime flags (--ipc=host, etc.)
- Model size / context length

## Benchmark Types

### Simple Tests (Does it work?)
- `pytorch-simple.sh` - Can PyTorch access GPU?
- `llama-simple.sh` - Can llama.cpp load model and generate tokens?
- `whisper-simple.sh` - Can whisper.cpp transcribe audio?

Run these FIRST to identify which configurations work at all.

### Performance Benchmarks (How well does it work?)
- `pytorch-gemm.sh` - Matrix multiplication TFLOPS
- `llama-bench.sh` - Prompt processing and token generation t/s
- `whisper-bench.sh` - Transcription speed (realtime multiplier)

Run these ONLY on working configurations.

### Extended Benchmarks (Deep performance analysis)
- Multiple model sizes
- Multiple context lengths
- Long-running stress tests
- Memory bandwidth analysis

These are expensive. Run on promising configurations only.

## Example Experiment: ROCm Version Comparison

```bash
# Create experiment
cp -r experiments/TEMPLATE experiments/2026-01-26_rocm-version-comparison
cd experiments/2026-01-26_rocm-version-comparison

# Record environment
./record-environment.sh > ENVIRONMENT.txt

# Edit run-all-benchmarks.sh
# Set IMAGES to:
#   softab:llama-hip-rocm644
#   softab:llama-hip-rocm711
#   softab:llama-hip-rocm72

# Run
./run-all-benchmarks.sh

# Results in raw_results/:
#   softab__llama-hip-rocm644_llama_simple.log
#   softab__llama-hip-rocm644_llama_bench.log
#   softab__llama-hip-rocm711_llama_simple.log (might fail!)
#   softab__llama-hip-rocm72_llama_simple.log
#   softab__llama-hip-rocm72_llama_bench.log

# Analyze with Claude:
# "Analyze these benchmark results. Which ROCm version works best?"
```

## Best Practices

1. **One experiment = One constant environment**
   - Don't change kernel/firmware mid-experiment
   - Reboot if needed before starting

2. **Test systematically**
   - Run simple tests first (identify what works)
   - Run benchmarks second (measure performance)
   - Run extended tests last (deep analysis)

3. **Embrace failures**
   - Most configs will fail - that's expected
   - Capture error messages in raw_results/*.log
   - Document failure patterns in FINDINGS.md
   - Example: "All Fedora ROCm packages fail on kernel 6.18.6 with 'invalid device function'"

4. **Document everything**
   - Record environment before starting
   - Note any anomalies during testing
   - Summarize findings with LLM analysis
   - Create a compatibility matrix (what works, what fails, why)

5. **Separate images from benchmarks**
   - Build images once
   - Run benchmarks separately
   - Reuse benchmark scripts across experiments

6. **Version control**
   - Commit ENVIRONMENT.txt and FINDINGS.md
   - Git ignore raw_results/ (too large)
   - Keep summary data only

## Understanding Failures

**Good failure documentation helps everyone:**

```markdown
# FINDINGS.md example

## Environment
- Kernel: 6.18.6-200.fc43
- Firmware: linux-firmware-20260110

## Results

### ✅ Working Configurations
- softab:llama-vulkan-radv - 45 t/s prompt processing
- softab:llama-therock - 38 t/s prompt processing

### ❌ Failed Configurations
- softab:llama-hip-rocm644
  Error: "invalid device function"
  Cause: Standard ROCm packages don't support kernel 6.18.6

- softab:pytorch-rocm72-fedora
  Error: Build fails with missing gfx1151 kernels
  Cause: Fedora ROCm packages lack gfx1151 support

## Conclusion
Kernel 6.18.6 requires TheRock nightlies or Vulkan backend.
Standard ROCm packages are incompatible.
```

This documentation prevents others from wasting time on known-broken combinations.
