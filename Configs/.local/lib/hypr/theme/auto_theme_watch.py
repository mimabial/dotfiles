#!/usr/bin/env python3
import ctypes
import os
import select
import struct
import sys
import threading
from pathlib import Path


class InotifyPathWatcher:
    """Lightweight inotify file watcher using ctypes."""

    IN_ATTRIB = 0x00000004
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_DELETE = 0x00000200
    EVENT_MASK = (
        IN_ATTRIB
        | IN_CLOSE_WRITE
        | IN_MOVED_FROM
        | IN_MOVED_TO
        | IN_CREATE
        | IN_DELETE
    )
    HEADER_SIZE = struct.calcsize("iIII")

    def __init__(self, on_change):
        self.on_change = on_change
        self.fd = None
        self.libc = None
        self._stop_event = threading.Event()
        self._thread = None
        self._lock = threading.Lock()
        self._targets_by_dir: dict[str, set[str]] = {}
        self._watches: dict[int, str] = {}

    def start(self, paths: list[Path]) -> bool:
        try:
            self.libc = ctypes.CDLL("libc.so.6", use_errno=True)
            self.libc.inotify_init.restype = ctypes.c_int
            self.libc.inotify_add_watch.argtypes = [
                ctypes.c_int,
                ctypes.c_char_p,
                ctypes.c_uint32,
            ]
            self.libc.inotify_add_watch.restype = ctypes.c_int
            self.libc.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]
            self.libc.inotify_rm_watch.restype = ctypes.c_int
            self.fd = self.libc.inotify_init()
            if self.fd < 0:
                self.fd = None
                return False
        except Exception:
            self.fd = None
            return False

        self._configure(paths)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        return True

    def _configure(self, paths: list[Path]):
        targets: dict[str, set[str]] = {}
        for path in paths:
            parent = path.parent
            try:
                parent.mkdir(parents=True, exist_ok=True)
            except Exception:
                continue
            targets.setdefault(str(parent), set()).add(path.name)

        with self._lock:
            self._targets_by_dir = targets
            self._reset_watches_locked()

    def _reset_watches_locked(self):
        if self.fd is None or self.libc is None:
            return

        for wd in list(self._watches.keys()):
            try:
                self.libc.inotify_rm_watch(self.fd, wd)
            except Exception:
                pass
        self._watches.clear()

        for dir_path in sorted(self._targets_by_dir.keys()):
            try:
                wd = self.libc.inotify_add_watch(
                    self.fd,
                    dir_path.encode(),
                    self.EVENT_MASK,
                )
            except Exception:
                wd = -1
            if wd >= 0:
                self._watches[wd] = dir_path

    def _run(self):
        while not self._stop_event.is_set():
            if self.fd is None:
                break
            try:
                ready, _, _ = select.select([self.fd], [], [], 1.0)
            except Exception:
                break

            if not ready:
                continue

            try:
                data = os.read(self.fd, 4096)
            except Exception:
                continue

            i = 0
            while i + self.HEADER_SIZE <= len(data):
                wd, _mask, _cookie, name_len = struct.unpack_from("iIII", data, i)
                i += self.HEADER_SIZE
                raw_name = data[i : i + name_len]
                i += name_len
                if name_len <= 0:
                    continue

                name = raw_name.split(b"\0", 1)[0].decode("utf-8", errors="ignore")
                if not name:
                    continue

                with self._lock:
                    dir_path = self._watches.get(wd)
                    if not dir_path:
                        continue
                    if name not in self._targets_by_dir.get(dir_path, set()):
                        continue
                    changed_path = Path(dir_path) / name

                try:
                    self.on_change(changed_path)
                except Exception as exc:
                    print(
                        f"Warning: auto-theme watcher callback failed for {changed_path}: {exc}",
                        file=sys.stderr,
                    )

    def stop(self):
        self._stop_event.set()
        if self.fd is not None:
            try:
                os.close(self.fd)
            except Exception:
                pass
            self.fd = None
        if self._thread is not None:
            self._thread.join(timeout=1.0)
        self._thread = None
