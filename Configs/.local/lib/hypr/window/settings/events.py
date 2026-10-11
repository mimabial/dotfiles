import ctypes
import os
import selectors
import signal
import struct
import subprocess
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO


@dataclass
class BackgroundCommand:
    process: subprocess.Popen
    output: TextIO | None
    on_complete: Callable[[int, str], None] | None


class SettingsEvents:
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_DELETE = 0x00000200
    FILE_EVENT_MASK = IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE
    FILE_EVENT_HEADER = struct.Struct("iIII")

    def __init__(self):
        self.selector = selectors.DefaultSelector()
        self.commands = {}
        self.watch_fd = None
        self.watch_directories = {}
        self.watched_paths = set()
        self.on_files_changed = None
        self.resize_pipe = None
        self.previous_resize_handler = None

    def watch_input(self, descriptor):
        self.selector.register(descriptor, selectors.EVENT_READ, lambda: None)

    def watch_resize(self, on_resize):
        self.resize_pipe = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
        self.previous_resize_handler = signal.signal(signal.SIGWINCH, self.queue_resize)
        def resized():
            os.read(self.resize_pipe[0], os.sysconf("SC_PAGESIZE"))
            on_resize()
        self.selector.register(self.resize_pipe[0], selectors.EVENT_READ, resized)

    def queue_resize(self, _signal, _frame):
        os.write(self.resize_pipe[1], b"r")

    def watch_files(self, paths, on_change):
        self.watched_paths = set(paths)
        self.on_files_changed = on_change
        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self.watch_fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.watch_fd < 0:
            raise OSError(ctypes.get_errno(), "Could not watch settings files")
        for directory in {path.parent for path in paths}:
            watch = libc.inotify_add_watch(self.watch_fd, os.fsencode(directory), self.FILE_EVENT_MASK)
            if watch < 0:
                raise OSError(ctypes.get_errno(), "Could not watch " + str(directory))
            self.watch_directories[watch] = directory
        self.selector.register(self.watch_fd, selectors.EVENT_READ, self.read_file_changes)

    def read_file_changes(self):
        events = os.read(self.watch_fd, os.sysconf("SC_PAGESIZE"))
        offset = 0
        changed = False
        while offset < len(events):
            watch, _mask, _cookie, name_bytes = self.FILE_EVENT_HEADER.unpack_from(events, offset)
            offset += self.FILE_EVENT_HEADER.size
            name = os.fsdecode(events[offset:offset + name_bytes].split(b"\0", 1)[0])
            offset += name_bytes
            directory = self.watch_directories.get(watch)
            changed |= directory is not None and Path(directory, name) in self.watched_paths
        if changed:
            self.on_files_changed()

    def start(self, command, on_complete=None, capture_output=False):
        output = tempfile.TemporaryFile(mode="w+", encoding="utf-8") if capture_output else None
        process = subprocess.Popen(command, stdout=output or subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        descriptor = os.pidfd_open(process.pid)
        self.commands[descriptor] = BackgroundCommand(process, output, on_complete)
        self.selector.register(descriptor, selectors.EVENT_READ, lambda: self.complete_command(descriptor))

    def complete_command(self, descriptor):
        command = self.commands.pop(descriptor)
        self.selector.unregister(descriptor)
        os.close(descriptor)
        code = command.process.wait()
        text = ""
        if command.output:
            command.output.seek(0)
            text = command.output.read()
            command.output.close()
        if command.on_complete:
            command.on_complete(code, text)

    def wait(self):
        for key, _events in self.selector.select():
            key.data()

    def close(self):
        if self.resize_pipe:
            signal.signal(signal.SIGWINCH, self.previous_resize_handler)
            for descriptor in self.resize_pipe:
                os.close(descriptor)
        for descriptor, command in self.commands.items():
            os.close(descriptor)
            if command.output:
                command.output.close()
        self.commands.clear()
        if self.watch_fd is not None:
            os.close(self.watch_fd)
        self.selector.close()
