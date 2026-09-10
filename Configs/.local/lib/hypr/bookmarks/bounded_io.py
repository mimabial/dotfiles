"""Bounded subprocess and regular-file I/O."""

from __future__ import annotations

import errno
import os
import selectors
import signal
import stat
import subprocess
import tempfile
import time
from pathlib import Path


class BoundedOutputError(ValueError):
    """A child process exceeded its declared output budget."""


def run_bounded_process(
    command: list[str],
    *,
    output_limit: int,
    timeout: float,
    input_data: bytes | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    """Capture stdout without allowing a child to fill unbounded memory."""
    if output_limit < 0 or timeout <= 0:
        raise ValueError("Process limits must be positive")

    input_stream = None
    process: subprocess.Popen[bytes] | None = None
    selector = selectors.DefaultSelector()
    output = bytearray()
    try:
        if input_data is not None:
            input_stream = tempfile.TemporaryFile()
            input_stream.write(input_data)
            input_stream.seek(0)

        deadline = time.monotonic() + timeout
        process = subprocess.Popen(
            command,
            stdin=input_stream if input_stream is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            start_new_session=True,
        )
        if process.stdout is None:
            raise OSError("Could not capture process output")
        selector.register(process.stdout, selectors.EVENT_READ)

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(command, timeout)
            events = selector.select(remaining)
            if not events:
                raise subprocess.TimeoutExpired(command, timeout)
            chunk = os.read(
                process.stdout.fileno(),
                min(64 * 1024, output_limit + 1 - len(output)),
            )
            if not chunk:
                break
            output.extend(chunk)
            if len(output) > output_limit:
                raise BoundedOutputError("Process output is too large")

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(command, timeout)
        return_code = process.wait(timeout=remaining)
        return subprocess.CompletedProcess(command, return_code, bytes(output), None)
    finally:
        selector.close()
        if process is not None:
            if process.stdout is not None:
                process.stdout.close()
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=0.25)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
        if input_stream is not None:
            input_stream.close()


def read_limited_bytes(
    path: Path,
    limit: int,
    description: str,
    *,
    follow_symlinks: bool = True,
) -> bytes:
    """Read one descriptor-validated regular file without blocking on special files."""
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK
    if not follow_symlinks:
        if not hasattr(os, "O_NOFOLLOW"):
            raise OSError("This platform cannot safely open fixed bookmark paths")
        flags |= os.O_NOFOLLOW

    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        if not follow_symlinks and error.errno == errno.ELOOP:
            raise ValueError(f"{description} path is not a regular file") from error
        raise

    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"{description} path is not a regular file")
        if info.st_size > limit:
            raise ValueError(f"{description} is too large")
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = -1
            raw = stream.read(limit + 1)
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    if len(raw) > limit:
        raise ValueError(f"{description} is too large")
    return raw


def read_limited_text(
    path: Path,
    limit: int,
    description: str,
    *,
    follow_symlinks: bool = True,
) -> str:
    """Read one bounded regular file as UTF-8 text."""
    return read_limited_bytes(
        path, limit, description, follow_symlinks=follow_symlinks
    ).decode("utf-8", errors="replace")


def existing_regular_mode(path: Path, description: str, default: int) -> int:
    """Return a fixed path's mode without following symlinks or special files."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return default
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"{description} path is not a regular file")
    return stat.S_IMODE(info.st_mode)


def atomic_write(path: Path, value: str | bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".tmp-", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(
            descriptor, "wb" if isinstance(value, bytes) else "w", encoding=None if isinstance(value, bytes) else "utf-8"
        ) as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
