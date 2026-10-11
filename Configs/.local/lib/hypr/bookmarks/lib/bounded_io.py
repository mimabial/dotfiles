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

from pyutils.child_process import exits_within


class BoundedOutputError(ValueError):
    pass


READ_CHUNK_BYTES = 64 * 1024
TERMINATE_GRACE_SECONDS = 0.25


def _remaining_seconds(deadline: float, command: list[str], timeout_seconds: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(command, timeout_seconds)
    return remaining


def _read_stdout_with_limit(
    process: subprocess.Popen[bytes],
    selector: selectors.BaseSelector,
    deadline: float,
    max_output_bytes: int,
    command: list[str],
    timeout_seconds: float,
) -> bytes:
    output = bytearray()
    while True:
        if not selector.select(_remaining_seconds(deadline, command, timeout_seconds)):
            raise subprocess.TimeoutExpired(command, timeout_seconds)
        chunk = os.read(
            process.stdout.fileno(),
            min(READ_CHUNK_BYTES, max_output_bytes + 1 - len(output)),
        )
        if not chunk:
            return bytes(output)
        output.extend(chunk)
        if len(output) > max_output_bytes:
            raise BoundedOutputError("Process output is too large")


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.stdout is not None:
        process.stdout.close()
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    if not exits_within(process, TERMINATE_GRACE_SECONDS):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()


def run_bounded_process(
    command: list[str],
    *,
    max_output_bytes: int,
    timeout_seconds: float,
    input_data: bytes | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    if max_output_bytes < 0 or timeout_seconds <= 0:
        raise ValueError("Process limits must be positive")

    input_stream = None
    process: subprocess.Popen[bytes] | None = None
    selector = selectors.DefaultSelector()
    try:
        if input_data is not None:
            input_stream = tempfile.TemporaryFile()
            input_stream.write(input_data)
            input_stream.seek(0)

        deadline = time.monotonic() + timeout_seconds
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

        output = _read_stdout_with_limit(process, selector, deadline, max_output_bytes, command, timeout_seconds)
        if not exits_within(process, _remaining_seconds(deadline, command, timeout_seconds)):
            raise subprocess.TimeoutExpired(command, timeout_seconds)
        return subprocess.CompletedProcess(command, process.wait(), output, None)
    finally:
        selector.close()
        if process is not None:
            _terminate_process_group(process)
        if input_stream is not None:
            input_stream.close()


def read_limited_bytes(
    path: Path,
    max_bytes: int,
    description: str,
    *,
    follow_symlinks: bool = True,
) -> bytes:
    """Validated by descriptor, so a FIFO or device file cannot block the read."""
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
        if info.st_size > max_bytes:
            raise ValueError(f"{description} is too large")
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = -1
            raw = stream.read(max_bytes + 1)
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    if len(raw) > max_bytes:
        raise ValueError(f"{description} is too large")
    return raw


def read_limited_text(
    path: Path,
    max_bytes: int,
    description: str,
    *,
    follow_symlinks: bool = True,
) -> str:
    return read_limited_bytes(
        path, max_bytes, description, follow_symlinks=follow_symlinks
    ).decode("utf-8", errors="replace")


def existing_regular_mode(path: Path, description: str, default: int) -> int:
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
