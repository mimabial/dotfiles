#!/usr/bin/env python
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyutils.logger as logger
import pyutils.pip_env as pip_env

pip_env.ensure_managed_interpreter()

logger = logger.get_logger()

try:
    pyamdgpuinfo = pip_env.v_import("pyamdgpuinfo")
except ImportError:
    pyamdgpuinfo = None


def format_frequency(frequency_hz: int) -> str:
    """
    Takes a frequency (in Hz) and normalizes it: `Hz`, `MHz`, or `GHz`

    Returns:
        str: frequency string with the appropriate suffix applied
    """
    return (
        format_size(frequency_hz, binary=False)
        .replace("B", "Hz")
        .replace("bytes", "Hz")
    )

def format_size(size: int, binary=True) -> str:
    """
    Format size in bytes to a human-readable format.

    Args:
        size (int): Size in bytes.
        binary (bool): If True, use binary (base 1024) units.

    Returns:
        str: Formatted size string.
    """
    suffixes = ["B", "KiB", "MiB", "GiB", "TiB"] if binary else ["B", "KB", "MB", "GB", "TB"]
    base = 1024 if binary else 1000
    index = 0

    while size >= base and index < len(suffixes) - 1:
        size /= base
        index += 1

    return f"{size:.0f} {suffixes[index]}"

def main():
    if pyamdgpuinfo is None:
        print("Unknown query failure: missing optional dependency 'pyamdgpuinfo'")
        return

    n_devices = pyamdgpuinfo.detect_gpus()
    
    if n_devices == 0:
        print("No AMD GPUs detected.")
        return
    
    first_gpu = pyamdgpuinfo.get_gpu(0)
    
    try:
        temperature = first_gpu.query_temperature()
        temperature = f"{temperature:.0f}°C"  # Format temperature to 2 digits with "°C"
        
        core_clock_hz = first_gpu.query_sclk()  # In Hz
        formatted_core_clock = format_frequency(core_clock_hz)
        
        power_usage = first_gpu.query_power()

        gpu_load = first_gpu.query_load()
        formatted_gpu_load = f"{gpu_load:.1f}%"  # Format GPU load to 1 decimal place

        gpu_info = {
            "GPU Temperature": temperature,
            "GPU Load": formatted_gpu_load,
            "GPU Core Clock": formatted_core_clock,
            "GPU Power Usage": f"{power_usage} Watts"
        }
        
        json_output = json.dumps(gpu_info, ensure_ascii=False)

        print(json_output)
    
    except json.JSONDecodeError as e:  # Handle JSON decoding errors (e.g., invalid JSON)
        print(f"JSON Error: {str(e)}")
    except AttributeError as e:  # Handle attribute errors (e.g., method not found)
        print(f"Attribute Error: {str(e)}")
    except ValueError as e:  # Handle value errors (e.g., invalid value for formatting)
        print(f"Value Error: {str(e)}")
    except RuntimeError as e:  # Handle runtime errors (e.g., issues with querying the GPU)
        print(f"Runtime Error: {str(e)}")
    except OSError as e:  # Handle OS-related errors (e.g., hardware issues)
        print(f"OS Error: {str(e)}")
    except Exception as e:  # Handle any other unexpected errors
        print(f"Unexpected Error: {str(e)}")

if __name__ == "__main__":
    main()
