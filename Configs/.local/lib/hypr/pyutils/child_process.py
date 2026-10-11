from __future__ import annotations

import contextlib
import io
import os
import selectors
import subprocess
import tempfile
import time

EXIT_GRACE_SECONDS = 1
READ_CHUNK_BYTES = 64 * 1024
TEXT_ENCODING = io.TextIOWrapper(io.BytesIO()).encoding


def exits_within(process: subprocess.Popen, seconds: float | None) -> bool:
    if process.returncode is not None:
        return True
    pidfd = os.pidfd_open(process.pid)
    try:
        with selectors.DefaultSelector() as exit_watch:
            exit_watch.register(pidfd, selectors.EVENT_READ)
            return bool(exit_watch.select(seconds))
    finally:
        os.close(pidfd)


def reap(process: subprocess.Popen) -> int:
    if not exits_within(process, EXIT_GRACE_SECONDS):
        process.kill()
    return process.wait()


def stop(process: subprocess.Popen) -> int:
    process.terminate()
    return reap(process)


def _seconds_until(deadline: float | None) -> float | None:
    return None if deadline is None else deadline - time.monotonic()


def _output_until_closed(process: subprocess.Popen, deadline: float | None) -> list[bytes | None] | None:
    pipes = (process.stdout, process.stderr)
    collected = {pipe: bytearray() for pipe in pipes if pipe is not None}
    with selectors.DefaultSelector() as open_pipes:
        for pipe in collected:
            open_pipes.register(pipe, selectors.EVENT_READ)
        while open_pipes.get_map():
            ready = open_pipes.select(_seconds_until(deadline))
            if not ready:
                return None
            for key, _ in ready:
                chunk = os.read(key.fd, READ_CHUNK_BYTES)
                if chunk:
                    collected[key.fileobj] += chunk
                else:
                    open_pipes.unregister(key.fileobj)
    return [None if pipe is None else bytes(collected[pipe]) for pipe in pipes]


def _as_text(data: bytes | None) -> str | None:
    return None if data is None else io.TextIOWrapper(io.BytesIO(data)).read()


def run(
    command: list[str],
    *,
    timeout: float | None,
    input: bytes | str | None = None,
    capture_output: bool = False,
    text: bool = False,
    check: bool = False,
    stdout: int | None = None,
    stderr: int | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    if capture_output:
        stdout = stderr = subprocess.PIPE
    deadline = None if timeout is None else time.monotonic() + timeout
    with contextlib.ExitStack() as owned:
        stdin = None
        if input is not None:
            stdin = owned.enter_context(tempfile.TemporaryFile())
            stdin.write(input.encode(TEXT_ENCODING) if text else input)
            stdin.seek(0)
        process = owned.enter_context(subprocess.Popen(command, stdin=stdin, stdout=stdout, stderr=stderr, env=env))
        output = _output_until_closed(process, deadline)
        if output is None or not exits_within(process, _seconds_until(deadline)):
            process.kill()
            process.wait()
            raise subprocess.TimeoutExpired(command, timeout)
        returncode = process.wait()
    captured_stdout, captured_stderr = (_as_text(data) if text else data for data in output)
    if check and returncode:
        raise subprocess.CalledProcessError(returncode, command, captured_stdout, captured_stderr)
    return subprocess.CompletedProcess(command, returncode, captured_stdout, captured_stderr)
