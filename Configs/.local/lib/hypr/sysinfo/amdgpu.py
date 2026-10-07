#!/usr/bin/env python
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.pip_env as pip_env

pip_env.ensure_managed_interpreter()

try:
    pyamdgpuinfo = pip_env.v_import("pyamdgpuinfo")
except ImportError:
    pyamdgpuinfo = None


def format_frequency(frequency_hz: int) -> str:
    return format_size(frequency_hz, binary=False).replace("B", "Hz")

def format_size(size_bytes: int, binary=True) -> str:
    suffixes = ["B", "KiB", "MiB", "GiB", "TiB"] if binary else ["B", "KB", "MB", "GB", "TB"]
    base = 1024 if binary else 1000
    index = 0

    while size_bytes >= base and index < len(suffixes) - 1:
        size_bytes /= base
        index += 1

    return f"{size_bytes:.0f} {suffixes[index]}"

def main():
    if pyamdgpuinfo is None:
        print("Unknown query failure: missing optional dependency 'pyamdgpuinfo'")
        return

    gpu_count = pyamdgpuinfo.detect_gpus()
    
    if gpu_count == 0:
        print("No AMD GPUs detected.")
        return
    
    first_gpu = pyamdgpuinfo.get_gpu(0)
    
    try:
        temperature = first_gpu.query_temperature()
        temperature = f"{temperature:.0f}°C"
        
        core_clock_hz = first_gpu.query_sclk()
        formatted_core_clock = format_frequency(core_clock_hz)
        
        power_usage = first_gpu.query_power()

        gpu_load = first_gpu.query_load()
        formatted_gpu_load = f"{gpu_load:.1f}%"

        gpu_info = {
            "GPU Temperature": temperature,
            "GPU Load": formatted_gpu_load,
            "GPU Core Clock": formatted_core_clock,
            "GPU Power Usage": f"{power_usage} Watts"
        }
        
        json_output = json.dumps(gpu_info, ensure_ascii=False)

        print(json_output)
    
    except Exception as error:
        print(f"{type(error).__name__}: {error}")

if __name__ == "__main__":
    main()
