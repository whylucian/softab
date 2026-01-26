#!/usr/bin/env python3
"""
GPU stress test for ROCm
Runs continuous compute workload to test stability and sustained performance
"""

import argparse
import json
import sys
import time
import threading
from dataclasses import dataclass
from typing import Optional

@dataclass
class StressResult:
    status: str
    duration_sec: float
    iterations: int = 0
    errors: int = 0
    avg_tflops: float = 0.0
    min_tflops: float = 0.0
    max_tflops: float = 0.0
    gpu_temp_start: Optional[float] = None
    gpu_temp_end: Optional[float] = None
    error_message: Optional[str] = None


def get_gpu_temp() -> Optional[float]:
    """Try to get GPU temperature via rocm-smi"""
    try:
        import subprocess
        result = subprocess.run(
            ["rocm-smi", "--showtemp"],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.split('\n'):
            if 'c' in line.lower():
                # Parse temperature like "42.0c"
                import re
                match = re.search(r'(\d+\.?\d*)c', line.lower())
                if match:
                    return float(match.group(1))
    except Exception:
        pass
    return None


def run_stress_test(duration_sec: int = 30, memory_limit_gb: int = 16):
    try:
        import torch
    except ImportError:
        return StressResult(
            status="error",
            duration_sec=0,
            error_message="PyTorch not installed"
        )

    if not torch.cuda.is_available():
        return StressResult(
            status="error",
            duration_sec=0,
            error_message="CUDA/ROCm not available"
        )

    device = torch.device("cuda")

    # Calculate matrix size based on memory limit (use ~50% for headroom)
    max_bytes = (memory_limit_gb * 1024 * 1024 * 1024) // 2
    max_elements = max_bytes // (3 * 2)  # 3 matrices, FP16
    size = min(8192, int(max_elements ** 0.5))
    # Round down to power of 2
    size = 2 ** (size.bit_length() - 1)

    result = StressResult(
        status="running",
        duration_sec=duration_sec
    )

    result.gpu_temp_start = get_gpu_temp()

    try:
        # Allocate matrices
        a = torch.randn(size, size, dtype=torch.float16, device=device)
        b = torch.randn(size, size, dtype=torch.float16, device=device)
        torch.cuda.synchronize()

        flops_per_iter = 2 * size * size * size
        tflops_samples = []

        start_time = time.perf_counter()
        end_time = start_time + duration_sec

        while time.perf_counter() < end_time:
            try:
                iter_start = time.perf_counter()
                c = torch.mm(a, b)
                torch.cuda.synchronize()
                iter_end = time.perf_counter()

                elapsed = iter_end - iter_start
                tflops = (flops_per_iter / elapsed) / 1e12
                tflops_samples.append(tflops)
                result.iterations += 1

                # Accumulate result to prevent optimization
                a[0, 0] = c[0, 0]

            except RuntimeError as e:
                result.errors += 1
                if result.errors > 10:
                    result.error_message = f"Too many errors: {str(e)}"
                    break

        actual_duration = time.perf_counter() - start_time
        result.duration_sec = round(actual_duration, 2)

        if tflops_samples:
            result.avg_tflops = round(sum(tflops_samples) / len(tflops_samples), 2)
            result.min_tflops = round(min(tflops_samples), 2)
            result.max_tflops = round(max(tflops_samples), 2)

        result.status = "success" if result.errors == 0 else "completed_with_errors"

        # Cleanup
        del a, b, c
        torch.cuda.empty_cache()

    except Exception as e:
        result.status = "error"
        result.error_message = str(e)

    result.gpu_temp_end = get_gpu_temp()

    return result


def main():
    parser = argparse.ArgumentParser(description="GPU stress test")
    parser.add_argument("--duration", type=int, default=30,
                        help="Test duration in seconds (default: 30)")
    parser.add_argument("--memory-limit", type=int, default=16,
                        help="Memory limit in GB (default: 16)")
    args = parser.parse_args()

    result = run_stress_test(args.duration, args.memory_limit)

    output = {
        "status": result.status,
        "duration_sec": result.duration_sec,
        "iterations": result.iterations,
        "errors": result.errors,
        "avg_tflops": result.avg_tflops,
        "min_tflops": result.min_tflops,
        "max_tflops": result.max_tflops,
        "gpu_temp_start_c": result.gpu_temp_start,
        "gpu_temp_end_c": result.gpu_temp_end,
    }

    if result.error_message:
        output["error_message"] = result.error_message

    print(json.dumps(output, indent=2))

    return 0 if result.status == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
