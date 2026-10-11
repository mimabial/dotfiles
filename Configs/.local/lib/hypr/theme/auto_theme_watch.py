#!/usr/bin/env python3
import ctypes
import os
import struct
from pathlib import Path


class InotifyPathWatcher:

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
    HEADER_FORMAT = "iIII"
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
    READ_SIZE = 4096

    def __init__(self):
        self.fd = None
        self._targets_by_dir: dict[str, set[str]] = {}
        self._watches: dict[int, str] = {}

    def start(self, paths: list[Path]) -> bool:
        try:
            libc = ctypes.CDLL("libc.so.6", use_errno=True)
            libc.inotify_init1.argtypes = [ctypes.c_int]
            libc.inotify_init1.restype = ctypes.c_int
            libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            libc.inotify_add_watch.restype = ctypes.c_int
            fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        except (OSError, AttributeError):
            return False
        if fd < 0:
            return False
        self.fd = fd

        for path in paths:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
            except OSError:
                continue
            self._targets_by_dir.setdefault(str(path.parent), set()).add(path.name)

        for dir_path in sorted(self._targets_by_dir):
            wd = libc.inotify_add_watch(fd, dir_path.encode(), self.EVENT_MASK)
            if wd >= 0:
                self._watches[wd] = dir_path
        return True

    def read_changed_paths(self) -> list[Path]:
        changed: list[Path] = []
        while True:
            try:
                data = os.read(self.fd, self.READ_SIZE)
            except BlockingIOError:
                return changed

            offset = 0
            while offset + self.HEADER_SIZE <= len(data):
                wd, _mask, _cookie, name_len = struct.unpack_from(self.HEADER_FORMAT, data, offset)
                offset += self.HEADER_SIZE
                name = data[offset : offset + name_len].split(b"\0", 1)[0].decode("utf-8", errors="ignore")
                offset += name_len
                dir_path = self._watches.get(wd)
                if name and dir_path and name in self._targets_by_dir[dir_path]:
                    changed.append(Path(dir_path) / name)

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
