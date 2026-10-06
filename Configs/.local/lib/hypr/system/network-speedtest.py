#!/usr/bin/env python3
import json
import signal
import subprocess
import sys

DOWNLOAD_BYTES = 25_000_000
UPLOAD_BYTES = 10_000_000
DEADLINE_SECONDS = 30
process = None
result = {}


def emit(**values):
    result.update(values)
    print(json.dumps(result), flush=True)


def cancel(signum, frame):
    if process is not None:
        process.terminate()
        process.wait()
    sys.exit(128 + signum)


signal.signal(signal.SIGTERM, cancel)
signal.signal(signal.SIGINT, cancel)
try:
    for direction, size in [("download", DOWNLOAD_BYTES), ("upload", UPLOAD_BYTES)]:
        emit(phase=direction)
        command = ["curl", "--fail", "--silent", "--show-error", "--max-time", str(DEADLINE_SECONDS), "--output", "/dev/null", "--write-out", "%{speed_" + direction + "}"]
        if direction == "download":
            command += ["https://speed.cloudflare.com/__down?bytes=" + str(size)]
        else:
            command += ["--data-binary", "@-", "https://speed.cloudflare.com/__up"]
        process = subprocess.Popen(command, stdin=subprocess.PIPE if direction == "upload" else subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output, error = process.communicate(b"\0" * size if direction == "upload" else None)
        if process.returncode:
            raise ValueError(error.decode().strip() or "The speed test failed.")
        emit(**{direction: round(float(output) * 8 / 1_000_000, 2)})
    emit(phase="complete")
except (ValueError, OSError) as error:
    emit(phase="failed", error=str(error))
    sys.exit(1)
