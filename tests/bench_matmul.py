#!/usr/bin/env python3
"""
Matrix multiplication benchmark for ROCm/PyTorch
Tests GEMM performance at various sizes with memory constraints
"""

import argparse
import json
import sys
import time

def run_benchmark(memory_limit_gb: int = 16):
    try:
        import torch
    except ImportError:
        return {"status": "error", "error": "PyTorch not installed"}

    results = {
        "status": "success",
        "pytorch_version": torch.__version__,
        "rocm_version": getattr(torch.version, 'hip', None),
        "cuda_available": torch.cuda.is_available(),
        "benchmarks": []
    }

    if not torch.cuda.is_available():
        results["status"] = "error"
        results["error"] = "CUDA/ROCm not available"
        return results

    device = torch.device("cuda")
    results["device_name"] = torch.cuda.get_device_name(0)
    results["device_count"] = torch.cuda.device_count()

    # Calculate max matrix size based on memory limit
    # Each FP16 element = 2 bytes, need 3 matrices (A, B, C)
    max_bytes = memory_limit_gb * 1024 * 1024 * 1024
    max_elements_per_matrix = max_bytes // (3 * 2)  # 3 matrices, 2 bytes each
    max_dim = int(max_elements_per_matrix ** 0.5)

    # Test sizes (powers of 2, capped by memory)
    sizes = [512, 1024, 2048, 4096, 8192, 16384]
    sizes = [s for s in sizes if s <= max_dim]

    results["memory_limit_gb"] = memory_limit_gb
    results["max_matrix_dim"] = max_dim
    results["test_sizes"] = sizes

    for size in sizes:
        try:
            # Warmup
            a = torch.randn(size, size, dtype=torch.float16, device=device)
            b = torch.randn(size, size, dtype=torch.float16, device=device)
            torch.cuda.synchronize()

            # Warmup run
            _ = torch.mm(a, b)
            torch.cuda.synchronize()

            # Timed runs
            iterations = 10
            start = time.perf_counter()
            for _ in range(iterations):
                c = torch.mm(a, b)
            torch.cuda.synchronize()
            end = time.perf_counter()

            elapsed = (end - start) / iterations
            # FLOPS = 2 * M * N * K for matrix multiply
            flops = 2 * size * size * size
            tflops = (flops / elapsed) / 1e12

            results["benchmarks"].append({
                "size": size,
                "dtype": "float16",
                "time_ms": elapsed * 1000,
                "tflops": round(tflops, 2)
            })

            # Cleanup
            del a, b, c
            torch.cuda.empty_cache()

        except RuntimeError as e:
            results["benchmarks"].append({
                "size": size,
                "dtype": "float16",
                "status": "error",
                "error": str(e)
            })
            break

    # Find peak performance
    successful = [b for b in results["benchmarks"] if "tflops" in b]
    if successful:
        peak = max(successful, key=lambda x: x["tflops"])
        results["peak_tflops"] = peak["tflops"]
        results["peak_size"] = peak["size"]

    return results


def main():
    parser = argparse.ArgumentParser(description="Matrix multiplication benchmark")
    parser.add_argument("--memory-limit", type=int, default=16,
                        help="Memory limit in GB (default: 16)")
    args = parser.parse_args()

    results = run_benchmark(args.memory_limit)
    print(json.dumps(results, indent=2))

    return 0 if results["status"] == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
