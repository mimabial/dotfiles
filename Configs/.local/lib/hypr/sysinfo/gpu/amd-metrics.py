#!/usr/bin/env python3
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from pyutils.managed_venv import import_managed_dependency, reexec_in_managed_environment

reexec_in_managed_environment()
HERTZ_PER_MHZ = 1_000_000
PERCENT_PER_WHOLE = 100


def read_amd_metrics():
    pyamdgpuinfo = import_managed_dependency("pyamdgpuinfo")
    if not pyamdgpuinfo.detect_gpus():
        raise RuntimeError("No AMD GPUs detected")
    gpu = pyamdgpuinfo.get_gpu(0)
    return {
        "temperature_c": round(gpu.query_temperature()),
        "utilization_percent": round(gpu.query_load() * PERCENT_PER_WHOLE, 1),
        "clock_mhz": gpu.query_sclk() / HERTZ_PER_MHZ,
        "power_w": gpu.query_power(),
    }


if __name__ == "__main__":
    try:
        print(json.dumps(read_amd_metrics(), ensure_ascii=False))
    except Exception as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(1)
