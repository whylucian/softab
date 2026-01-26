# Experiment Template

Copy this directory to start a new experiment run.

## Non-Mutable Variables (Record Once Per Experiment)

These variables MUST remain constant for all tests in this experiment:

```
Kernel Version:
Kernel Parameters:
Linux Distribution:
Linux Version:
Firmware Version:
Hardware:
GPU:
Memory Config (GART/GTT):
Date:
```

## Mutable Variables (What We're Testing)

Document which variables you're testing in this experiment:

- [ ] ROCm version
- [ ] Backend (Vulkan vs HIP)
- [ ] Vulkan driver (RADV vs AMDVLK)
- [ ] GFX target (gfx1100/1150/1151/1152)
- [ ] Python version
- [ ] Environment variables
- [ ] Flash Attention
- [ ] Container runtime flags
- [ ] Other: ___________

## Running the Experiment

```bash
# 1. Record system configuration
./record-environment.sh > ENVIRONMENT.txt

# 2. Run all benchmarks
./run-all-benchmarks.sh

# 3. Results will be saved to raw_results/
```

## Analysis

After completing the experiment, document findings in FINDINGS.md using LLM analysis of raw results.
