#!/usr/bin/python3

from __future__ import annotations

import itertools
import errno
import json
import os
import re
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request

CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
REAL_FS = {
    "ext2", "ext3", "ext4", "xfs", "btrfs", "f2fs", "vfat", "exfat", "ntfs",
    "ntfs3", "fuseblk", "zfs", "jfs", "reiserfs", "apfs", "hfsplus", "bcachefs", "msdos",
}
NETWORK_FS = {
    "nfs", "nfs4", "cifs", "smb3", "smbfs", "ceph", "glusterfs", "9p", "fuse.sshfs",
    "fuse.rclone", "davfs",
}
FAT_SLOW_MOUNT_FLAGS = ("flush", "sync", "dirsync")
UDISKS_MOUNT_ROOTS = ("/run/media/", "/media/")
CRYPT_DM_UUID_PREFIX = "CRYPT-"
LUKS2_DM_UUID_PREFIX = "CRYPT-LUKS2-"
LVM_DM_UUID_PREFIX = "LVM-"
NETWORK_STATVFS_TIMEOUT = 0.8
DRIVE_FD_LIMIT = 256
PROCESS_WARM_UP_SECONDS = 0.25
NVIDIA_READ_WINDOW_SECONDS = 0.5
NVIDIA_SUSPEND_MARGIN_SECONDS = 1.0
NVIDIA_SUSPEND_DELAY_SECONDS = 5.0
BY_ID_PREFIX_RANKS = ("nvme-", "ata-", "usb-", "mmc-", "virtio-", "scsi-")
BY_ID_BUS_RANK = len(BY_ID_PREFIX_RANKS)
BY_ID_FALLBACK_RANK = BY_ID_BUS_RANK + 1
SECTOR_BYTES = 512
CPU_TEMP_PREFERENCE = ("k10temp", "zenpower", "coretemp", "cpu_thermal", "soc_thermal", "acpitz")
GPU_TEMP_HWMON = ("amdgpu", "nouveau", "i915", "xe", "radeon")
PROC_LIMIT = 6
FULL_LIMIT = 400
CONNECTION_LIMIT = 12
CONTROL_LINE_LIMIT = 4 * 1024
EXTERNAL_TEXT_LIMIT = 512
STREAM_LINE_LIMIT = 64 * 1024
FILE_READ_LIMIT = 1024 * 1024
COMMAND_OUTPUT_LIMIT = 1024 * 1024
OUTPUT_LINE_LIMIT = 512 * 1024
DIRECTORY_ENTRY_LIMIT = 4096
PROCESS_SCAN_LIMIT = 16_384
FD_SCAN_LIMIT = 4096
SOCKET_SCAN_LIMIT = 16_384
PROC_FILE_LIMIT = 64 * 1024
DETAIL_NONE = 0
DETAIL_TOP_PROCESSES = 1
DETAIL_ALL_PROCESSES = 2
PATH_TEXT_LIMIT = 4096
FIELD_TEXT_LIMIT = 64
SSID_TEXT_LIMIT = 128
VOLUME_LIMIT = 256
PERIPHERAL_LIMIT = 256
MIN_VOLUME_BYTES = 64 * 1024 * 1024
MAX_DEVICE_STACK_DEPTH = 4
MAX_PLAUSIBLE_MILLIDEGREES = 200_000
KERNEL_COMM_LENGTH = 15
SENSOR_RESCAN_SECONDS = 30
DETAIL_REFRESH_SECONDS = 10
VOLUMES_REFRESH_SECONDS = 10
PLAIN_NAME_MAX_LENGTH = 128
IDLE_REFRESH_SECONDS = 30
MAX_RATE_GAP_SECONDS = 5.0
SLOW_SAMPLE_SECONDS = 0.95
MIN_INTERVAL_SECONDS = 0.1
MAX_INTERVAL_SECONDS = 30.0
TOOL_DIRS = ("/usr/bin", "/bin")
PCI_IDS_PATH = "/usr/share/hwdata/pci.ids"
POWER_SUPPLY_DIR = "/sys/class/power_supply"
MAINS_SUPPLY_TYPES = ("Mains", "USB", "USB_PD", "USB_C")
RTMGRP_IPV4_IFADDR = 0x10
RTMGRP_IPV4_ROUTE = 0x40
RTMGRP_IPV6_IFADDR = 0x100
RTMGRP_IPV6_ROUTE = 0x400
ROUTING_EVENT_GROUPS = RTMGRP_IPV4_IFADDR | RTMGRP_IPV4_ROUTE | RTMGRP_IPV6_IFADDR | RTMGRP_IPV6_ROUTE
NETLINK_RECEIVE_BYTES = 64 * 1024


def encode_payload(payload: dict) -> bytes:
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    if len(encoded) <= OUTPUT_LINE_LIMIT:
        return encoded + b"\n"
    fallback = {
        "seq": payload.get("seq", 0),
        "t": payload.get("t", time.time()),
        "elapsed": payload.get("elapsed", 0),
        "interval": payload.get("interval", 1),
        "errors": [f"sample exceeded {OUTPUT_LINE_LIMIT}-byte output limit"],
    }
    return json.dumps(fallback, separators=(",", ":")).encode("utf-8") + b"\n"


def bounded_text(value: str, limit: int = EXTERNAL_TEXT_LIMIT) -> str:
    encoded = value.encode("utf-8", "replace")
    if len(encoded) <= limit:
        return value
    return encoded[:limit].decode("utf-8", "ignore")


def bounded_directory_names(path: str, limit: int = DIRECTORY_ENTRY_LIMIT) -> list[str]:
    names: list[str] = []
    try:
        with os.scandir(path) as entries:
            for entry in entries:
                if len(names) >= limit:
                    return []
                names.append(entry.name)
    except OSError:
        return []
    names.sort()
    return names


def fd_targets(pid: str):
    for fd in bounded_directory_names(f"/proc/{pid}/fd", FD_SCAN_LIMIT):
        try:
            yield fd, os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            pass


def read_raw(path: str, limit: int = FILE_READ_LIMIT) -> bytearray | None:
    raw = bytearray()
    try:
        with open(path, "rb", buffering=0) as handle:
            while len(raw) <= limit and (chunk := handle.read(PAGE_SIZE)):
                raw += chunk
    except OSError:
        return None
    return raw if len(raw) <= limit else None


def read_text(path: str, default: str = "") -> str:
    raw = read_raw(path)
    try:
        return default if raw is None else raw.decode("utf-8").strip()
    except UnicodeDecodeError:
        return default


def read_int(path: str, default: int | None = None) -> int | None:
    raw = read_text(path)
    if raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        try:
            return int(float(raw))
        except ValueError:
            return default


def read_float(path: str, default: float | None = None) -> float | None:
    raw = read_text(path)
    if raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def trusted_helper_path(program: str) -> str | None:
    if not program or "/" in program:
        return None
    for directory in TOOL_DIRS:
        candidate = os.path.join(directory, program)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def kill_process_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (OSError, ProcessLookupError):
        pass


def run(cmd: list[str], timeout: float = 2.0) -> str:
    if not cmd:
        return ""
    executable = trusted_helper_path(cmd[0])
    if executable is None:
        return ""
    try:
        proc = subprocess.Popen(
            [executable, *cmd[1:]],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return ""
    assert proc.stdout is not None
    output = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    exit_watch = os.pidfd_open(proc.pid)
    selector.register(exit_watch, selectors.EVENT_READ)
    os.set_blocking(proc.stdout.fileno(), False)
    deadline = time.monotonic() + timeout
    eof = False
    exited = False
    try:
        while not (eof and exited):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                kill_process_group(proc)
                proc.wait()
                return ""
            for key, _ in selector.select(remaining):
                if key.fileobj == exit_watch:
                    exited = True
                    selector.unregister(exit_watch)
                    kill_process_group(proc)
                    continue
                try:
                    chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    eof = True
                    selector.unregister(key.fileobj)
                    break
                if len(output) + len(chunk) > COMMAND_OUTPUT_LIMIT:
                    kill_process_group(proc)
                    proc.wait()
                    return ""
                output.extend(chunk)
        proc.wait()
        return output.decode("utf-8")
    except (OSError, UnicodeDecodeError, subprocess.SubprocessError):
        kill_process_group(proc)
        proc.wait()
        return ""
    finally:
        selector.close()
        os.close(exit_watch)
        proc.stdout.close()


def bounded_lines(stream, limit: int):
    while True:
        raw = stream.readline(limit + 2)
        if not raw:
            return
        oversized = len(raw.rstrip(b"\r\n")) > limit
        while raw and not raw.endswith(b"\n"):
            raw = stream.readline(64 * 1024)
            oversized = True
        if oversized:
            yield ""
            continue
        try:
            yield raw.rstrip(b"\r\n").decode("utf-8")
        except UnicodeDecodeError:
            yield ""


def parse_pressure(resource: str) -> tuple[float, float]:
    some = full = 0.0
    for kind, value in re.findall(r"^(some|full)\s+avg10=([0-9.]+)", read_text(f"/proc/pressure/{resource}"), re.M):
        if kind == "some":
            some = float(value)
        else:
            full = float(value)
    return some, full


def rate(now: float | None, prev: float | None, elapsed: float) -> float:
    if now is None or prev is None or elapsed <= 0:
        return 0.0
    delta = now - prev
    return max(0.0, delta / elapsed)


class CpuSampler:
    def __init__(self) -> None:
        self.prev_total: list[int] | None = None
        self.prev_cores: list[list[int]] | None = None
        self.static = self._static_info()
        self.temp_source = self._find_temp_source()
        self.freq_paths = [
            f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq"
            for i in range(self.static["threads"])
        ]
        self.freq_paths = [p for p in self.freq_paths if os.path.exists(p)]

    @staticmethod
    def _cpu_list(raw: str) -> list[int]:
        cpus: list[int] = []
        for part in raw.split(","):
            part = part.strip()
            if not part:
                continue
            try:
                if "-" in part:
                    lo, hi = (int(value) for value in part.split("-", 1))
                    if hi < lo or hi - lo > DIRECTORY_ENTRY_LIMIT:
                        return []
                    cpus.extend(range(lo, hi + 1))
                else:
                    cpus.append(int(part))
            except ValueError:
                continue
            if len(cpus) > DIRECTORY_ENTRY_LIMIT:
                return []
        return cpus

    def _static_info(self) -> dict:
        model = ""
        for line in read_text("/proc/cpuinfo").splitlines():
            if line.lower().startswith("model name"):
                model = line.split(":", 1)[1].strip()
                break
        threads = os.cpu_count() or 1
        core_ids = set()
        for i in range(threads):
            core = read_text(f"/sys/devices/system/cpu/cpu{i}/topology/core_id")
            pkg = read_text(f"/sys/devices/system/cpu/cpu{i}/topology/physical_package_id")
            if core != "":
                core_ids.add((pkg, core))
        cores = len(core_ids) or threads
        efficiency = self._cpu_list(read_text("/sys/devices/cpu_atom/cpus"))
        max_khz = read_int("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
        model = re.sub(r"\s+", " ", model)
        model = bounded_text(re.sub(r"\((R|TM)\)", "", model).replace("  ", " ").strip())
        return {
            "model": model,
            "cores": cores,
            "threads": threads,
            "efficiency": efficiency,
            "maxMhz": round(max_khz / 1000) if max_khz else 0,
        }

    def _find_temp_source(self) -> str | None:
        found: dict[str, str] = {}
        for hw in bounded_directory_names("/sys/class/hwmon"):
            base = f"/sys/class/hwmon/{hw}"
            name = read_text(f"{base}/name")
            if not name:
                continue
            for entry in bounded_directory_names(base):
                if not (entry.startswith("temp") and entry.endswith("_input")):
                    continue
                label = read_text(f"{base}/{entry[:-6]}_label").lower()
                key = f"{base}/{entry}"
                if name in ("k10temp", "zenpower") and label in ("tctl", "tdie", ""):
                    found.setdefault(name, key)
                elif name == "coretemp" and label.startswith("package"):
                    found.setdefault(name, key)
                elif name in ("cpu_thermal", "soc_thermal", "acpitz"):
                    found.setdefault(name, key)
                elif label == "cpu":
                    found.setdefault("labelled", key)
        for pref in CPU_TEMP_PREFERENCE:
            if pref in found:
                return found[pref]
        if "labelled" in found:
            return found["labelled"]
        for zone in bounded_directory_names("/sys/class/thermal"):
            if not zone.startswith("thermal_zone"):
                continue
            ztype = read_text(f"/sys/class/thermal/{zone}/type").lower()
            if "cpu" in ztype or "x86_pkg" in ztype or "soc" in ztype:
                return f"/sys/class/thermal/{zone}/temp"
        return None

    def sample(self) -> dict:
        totals: list[int] | None = None
        cores: list[list[int]] = []
        for line in read_text("/proc/stat").splitlines():
            if not line.startswith("cpu"):
                continue
            parts = line.split()
            values = [int(v) for v in parts[1:]]
            if parts[0] == "cpu":
                totals = values
            else:
                cores.append(values)

        def split(now: list[int], prev: list[int] | None) -> tuple[float, float, float, float]:
            if prev is None or len(now) < 8:
                return 0.0, 0.0, 0.0, 0.0
            delta = [n - p for n, p in zip(now, prev)]
            total = sum(delta[:8])
            if total <= 0:
                return 0.0, 0.0, 0.0, 0.0
            user = (delta[0] + delta[1]) / total * 100
            system = (delta[2] + delta[5] + delta[6] + delta[7]) / total * 100
            iowait = delta[4] / total * 100
            idle = delta[3] / total * 100
            return user, system, iowait, 100 - idle - iowait

        user, system, iowait, busy = split(totals or [], self.prev_total)
        per_core: list[float] = []
        if self.prev_cores and len(self.prev_cores) == len(cores):
            for now, prev in zip(cores, self.prev_cores):
                per_core.append(round(split(now, prev)[3], 1))
        else:
            per_core = [0.0 for _ in cores]
        self.prev_total = totals
        self.prev_cores = cores

        mhz = 0
        if self.freq_paths:
            values = [read_int(p, 0) or 0 for p in self.freq_paths]
            values = [v for v in values if v > 0]
            if values:
                mhz = round(sum(values) / len(values) / 1000)
        if mhz == 0:
            speeds = re.findall(r"cpu MHz\s*:\s*([0-9.]+)", read_text("/proc/cpuinfo"))
            if speeds:
                mhz = round(sum(float(s) for s in speeds) / len(speeds))

        load = read_text("/proc/loadavg").split()[:3]
        uptime = read_text("/proc/uptime").split()
        temp = None
        if self.temp_source:
            raw = read_int(self.temp_source)
            if raw is not None:
                temp = round(raw / 1000, 1)

        return {
            "total": round(busy, 1),
            "user": round(user, 1),
            "system": round(system, 1),
            "iowait": round(iowait, 1),
            "cores": per_core,
            "mhz": mhz,
            "maxMhz": self.static["maxMhz"],
            "load": [float(v) for v in load] if len(load) == 3 else [0, 0, 0],
            "uptime": float(uptime[0]) if uptime else 0,
            "model": self.static["model"],
            "coreCount": self.static["cores"],
            "threadCount": self.static["threads"],
            "efficiency": self.static["efficiency"],
            "temp": temp,
        }


class RaplSampler:

    def __init__(self, base: str = "/sys/class/powercap") -> None:
        self.base = base
        self.previous: dict[str, int] = {}
        self.domains = [entry for entry in bounded_directory_names(base)
                        if re.fullmatch(r"intel-rapl:\d+(?::\d+)?", entry)]

    def sample(self, elapsed: float) -> dict:
        domains = []
        restricted = False
        for entry in self.domains:
            path = f"{self.base}/{entry}"
            name = bounded_text(read_text(f"{path}/name") or entry)
            energy_path = f"{path}/energy_uj"
            energy = read_int(energy_path)
            if energy is None:
                restricted |= os.path.exists(energy_path)
                self.previous.pop(entry, None)
                continue
            maximum = read_int(f"{path}/max_energy_range_uj") or 0
            previous = self.previous.get(entry)
            self.previous[entry] = energy
            watts = None
            if previous is not None and elapsed > 0:
                delta = energy - previous
                if delta < 0 and maximum > 0:
                    delta += maximum
                if delta >= 0:
                    watts = round(delta / 1_000_000 / elapsed, 3)
            domains.append({"id": entry, "name": name, "watts": watts})
        return {"domains": domains, "restricted": restricted}


def runtime_state(device: str) -> float | str:
    if read_text(f"{device}/power/control") != "auto":
        return "on"
    status = read_text(f"{device}/power/runtime_status")
    if status in ("suspended", "suspending"):
        return "suspended"
    if not status:
        return "on"
    milliseconds = read_int(f"{device}/power/autosuspend_delay_ms")
    return milliseconds / 1000 if milliseconds is not None and milliseconds >= 0 else NVIDIA_SUSPEND_DELAY_SECONDS


def nvidia_access(states: list, opened: float | None, now: float) -> tuple[str, bool]:
    if "suspended" in states:
        return "rest", False
    delays = [state for state in states if not isinstance(state, str)]
    if not delays:
        return "stream", False
    age = None if opened is None else now - opened
    if age is not None and age < NVIDIA_READ_WINDOW_SECONDS:
        return "query", False
    if age is not None and age < min(delays) + NVIDIA_SUSPEND_MARGIN_SECONDS:
        return "rest", False
    return "query", True


def normalize_slot(bus: str) -> str:
    parts = str(bus).strip().lower().split(":")
    if len(parts) == 3 and len(parts[0]) > 4:
        parts[0] = parts[0][-4:]
    return ":".join(parts)


def fdinfo_size(raw: str) -> int | None:
    parts = raw.split()
    if not parts or not parts[0].isdigit():
        return None
    scale = {None: 1, "KiB": 1 << 10, "MiB": 1 << 20, "GiB": 1 << 30}.get(parts[1] if len(parts) > 1 else None)
    return int(parts[0]) * scale if scale else None


def parse_drm_fdinfo(text: str) -> dict | None:
    client: dict = {"pdev": "", "id": "", "engines": {}, "regions": {}}
    legacy: dict[str, int] = {}

    def engine(name: str) -> dict:
        return client["engines"].setdefault(name, {"busy": 0, "total": None, "capacity": 1})

    for line in text.splitlines():
        key, separator, value = line.partition(":")
        if not separator:
            continue
        value = value.strip()
        if key == "drm-pdev":
            client["pdev"] = value
        elif key == "drm-client-id":
            client["id"] = value
        elif key.startswith("drm-engine-capacity-"):
            engine(key[20:])["capacity"] = max(1, read_number(value) or 1)
        elif key.startswith("drm-engine-"):
            engine(key[11:])["busy"] = read_number(value.removesuffix("ns")) or 0
        elif key.startswith("drm-total-cycles-"):
            engine(key[17:])["total"] = read_number(value)
        elif key.startswith("drm-cycles-"):
            engine(key[11:])["busy"] = read_number(value) or 0
        elif key.startswith(("drm-resident-", "drm-memory-")):
            size = fdinfo_size(value)
            if size is not None:
                (client["regions"] if key.startswith("drm-resident-") else legacy)[key.split("-", 2)[2]] = size
    if not client["pdev"] or not client["id"]:
        return None
    client["regions"] = client["regions"] or legacy
    return client


def read_number(raw: str) -> int | None:
    try:
        return int(raw.strip())
    except ValueError:
        return None


def client_memory(client: dict, integrated: bool) -> int:
    shared = ("gtt", "system", "stolen") if integrated else ()
    return sum(size for region, size in client["regions"].items() if region.startswith(("vram", "local") + shared))


def engine_shares(now: dict[str, dict], before: dict[str, dict], elapsed: float) -> dict[str, float]:
    shares: dict[str, float] = {}
    for name, counter in now.items():
        prev = before.get(name)
        if prev is None:
            continue
        busy = max(0, counter["busy"] - prev["busy"])
        if counter["total"] is not None and prev["total"] is not None:
            span = counter["total"] - prev["total"]
            share = busy / span if span > 0 else 0.0
        elif counter["total"] is None and prev["total"] is None and elapsed > 0:
            share = busy / (elapsed * 1e9)
        else:
            continue
        shares[name] = share / counter["capacity"] * 100
    return shares


def process_name(pid: int) -> str:
    stat = read_text(f"/proc/{pid}/stat")
    open_paren, close = stat.find("("), stat.rfind(")")
    return display_name(pid, stat[open_paren + 1:close]) if 0 <= open_paren < close else f"pid {pid}"


def parse_pmon(out: str, slots: dict[str, str]) -> list[dict]:
    columns: list[str] = []
    rows: list[dict] = []
    for line in out.splitlines():
        if line.startswith("#"):
            columns = columns or line[1:].split()
            continue
        parts = line.split()
        cell = {name: parts[index] for index, name in enumerate(columns) if index < len(parts)}
        slot = slots.get(cell.get("gpu", ""))
        pid = read_number(cell.get("pid", ""))
        if slot is None or pid is None:
            continue
        rows.append({
            "slot": slot, "pid": pid, "name": bounded_text(cell.get("command", "")),
            "util": read_number(cell.get("sm", "")) or 0, "mem": (read_number(cell.get("fb", "")) or 0) * 1024 * 1024,
        })
    return rows


def pci_name(device: str) -> str:
    vendor = read_text(f"{device}/vendor").removeprefix("0x")
    product = read_text(f"{device}/device").removeprefix("0x")
    in_vendor = False
    try:
        with open(PCI_IDS_PATH, encoding="utf-8", errors="replace") as ids:
            for line in ids:
                if line.startswith("#"):
                    continue
                if not line.startswith("\t"):
                    in_vendor = line.startswith(f"{vendor}  ")
                elif in_vendor and line.startswith(f"\t{product}  "):
                    name = line.strip()[len(product):].strip()
                    bracket = re.findall(r"\[([^\]]+)\]", name)
                    return bounded_text(bracket[-1] if bracket else name)
    except OSError:
        pass
    return ""


class GpuCard:
    def __init__(self, kind: str, device: str) -> None:
        self.kind = kind
        self.device = device
        self.slot = os.path.basename(os.path.realpath(device))
        self.boot_vga = read_text(f"{device}/boot_vga") == "1"
        self.integrated = kind == "intel" and self.slot.startswith("0000:00:")
        self.hwmon = next((f"{device}/hwmon/{hw}" for hw in bounded_directory_names(f"{device}/hwmon")), None)
        self.name = pci_name(device) or kind.upper()


class GpuSampler:

    QUERY = (
        "pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu,"
        "power.draw,clocks.gr,clocks.max.gr,fan.speed"
    )
    VENDORS = {"0x1002": "amd", "0x8086": "intel", "0x10de": "nvidia"}

    def __init__(self) -> None:
        self.latest: dict[str, dict] = {}
        self.lock = threading.Lock()
        self.proc: subprocess.Popen | None = None
        self.querying = False
        self.opened: float | None = None
        self.asleep: set[str] = set()
        self.nvidia_slots: dict[str, str] | None = None
        self.drm_fds: dict[str, tuple[int, list[str]]] = {}
        self.clients: dict[tuple[str, str], tuple[int, dict]] = {}
        self.clients_stamp: int | None = None
        self.engine_load: dict[str, float] | None = None
        self.client_usage: dict[tuple[str, int], list[float]] = {}
        cards: dict[str, GpuCard] = {}
        for card in bounded_directory_names("/sys/class/drm"):
            device = f"/sys/class/drm/{card}/device"
            kind = self.VENDORS.get(read_text(f"{device}/vendor").lower()) if re.fullmatch(r"card\d+", card) else None
            if kind:
                entry = GpuCard(kind, device)
                cards.setdefault(entry.slot, entry)
        self.cards = sorted(cards.values(), key=lambda card: (not card.boot_vga, card.slot))
        if self._nvidia_gate() == "query":
            self._query_nvidia()

    def _nvidia_gate(self) -> str:
        nvidia = [card for card in self.cards if card.kind == "nvidia"]
        if not nvidia or trusted_helper_path("nvidia-smi") is None:
            return "rest"
        now = time.monotonic()
        states = [runtime_state(card.device) for card in nvidia]
        self.asleep = {card.slot for card, state in zip(nvidia, states) if state == "suspended"}
        access, reopen = nvidia_access(states, self.opened, now)
        if reopen:
            self.opened = now
        if access != "stream":
            self.stop()
        elif not (self.proc and self.proc.poll() is None):
            self._start_nvidia()
        return access

    def _query_nvidia(self) -> None:
        with self.lock:
            if self.querying:
                return
            self.querying = True

        def query() -> None:
            try:
                for line in run(["nvidia-smi", f"--query-gpu={self.QUERY}", "--format=csv,noheader,nounits"]).splitlines():
                    self._store_nvidia(line)
            finally:
                with self.lock:
                    self.querying = False

        threading.Thread(target=query, daemon=True).start()

    def _start_nvidia(self) -> None:
        executable = trusted_helper_path("nvidia-smi")
        try:
            if executable is None:
                raise FileNotFoundError("nvidia-smi")
            self.proc = subprocess.Popen(
                [executable, f"--query-gpu={self.QUERY}", "--format=csv,noheader,nounits", "-l", "1"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            self.proc = None
            return
        threading.Thread(target=self._read_nvidia, args=(self.proc,), daemon=True).start()

    def _read_nvidia(self, proc: subprocess.Popen) -> None:
        assert proc.stdout
        for line in bounded_lines(proc.stdout, STREAM_LINE_LIMIT):
            self._store_nvidia(line)

    def _store_nvidia(self, line: str) -> None:
        parts = [part.strip() for part in line.strip().split(",")]
        if len(parts) < 10:
            return

        def num(value: str) -> float | None:
            try:
                return float(value)
            except ValueError:
                return None

        mem_used = num(parts[3])
        mem_total = num(parts[4])
        snapshot = {
            "name": bounded_text(parts[1]),
            "vendor": "nvidia",
            "util": num(parts[2]),
            "memUsed": mem_used * 1024 * 1024 if mem_used is not None else None,
            "memTotal": mem_total * 1024 * 1024 if mem_total is not None else None,
            "temp": num(parts[5]),
            "power": num(parts[6]),
            "mhz": num(parts[7]),
            "maxMhz": num(parts[8]),
            "fan": num(parts[9]),
        }
        with self.lock:
            self.latest[normalize_slot(parts[0])] = snapshot

    @staticmethod
    def _hwmon_value(hwmon: str | None, prefix: str, labels: tuple[str, ...]) -> float | None:
        if not hwmon:
            return None
        chosen = None
        for entry in bounded_directory_names(hwmon):
            if entry.startswith(prefix) and entry.endswith("_input"):
                label = read_text(f"{hwmon}/{entry[:-6]}_label").lower()
                if label in labels or chosen is None:
                    chosen = entry
                    if label in labels:
                        break
        return read_float(f"{hwmon}/{chosen}") if chosen else None

    def _drm_clients(self) -> list[tuple[int, dict]]:
        fds = {}
        found: list[tuple[int, dict]] = []
        for pid in filter(str.isdigit, bounded_directory_names("/proc", PROCESS_SCAN_LIMIT)):
            try:
                fd_count = os.stat(f"/proc/{pid}/fd").st_size
            except OSError:
                continue
            cached = self.drm_fds.get(pid)
            fds_unchanged = cached is not None and cached[0] == fd_count
            paths = cached[1] if fds_unchanged else [f"/proc/{pid}/fdinfo/{fd}" for fd, target in fd_targets(pid) if target.startswith("/dev/dri/")]
            client_paths: dict[tuple[str, str], str] = {}
            for path in paths:
                client = parse_drm_fdinfo(read_text(path))
                if client is not None and (client["pdev"], client["id"]) not in client_paths:
                    client_paths[client["pdev"], client["id"]] = path
                    found.append((int(pid), client))
            stale = fds_unchanged and len(client_paths) != len(paths)
            if not stale:
                fds[pid] = fd_count, list(client_paths.values())
        self.drm_fds = fds
        return found

    def _sample_clients(self) -> None:
        clients: dict[tuple[str, str], tuple[int, dict]] = {}
        for pid, client in self._drm_clients():
            clients.setdefault((client["pdev"], client["id"]), (pid, client))
        now = time.monotonic_ns()
        elapsed = (now - self.clients_stamp) / 1e9 if self.clients_stamp is not None else 0.0
        usable = 0.0 < elapsed < MAX_RATE_GAP_SECONDS
        integrated = {card.slot for card in self.cards if card.integrated}
        engines: dict[str, dict[str, float]] = {}
        usage: dict[tuple[str, int], list[float]] = {}
        for key, (pid, client) in clients.items():
            previous = self.clients.get(key)
            shares = engine_shares(client["engines"], previous[1]["engines"], elapsed) if usable and previous else {}
            for engine, share in shares.items():
                card = engines.setdefault(client["pdev"], {})
                card[engine] = card.get(engine, 0.0) + share
            total = usage.setdefault((client["pdev"], pid), [0.0, 0.0])
            total[0] += min(100.0, max(shares.values(), default=0.0))
            total[1] += client_memory(client, client["pdev"] in integrated)
        self.clients, self.clients_stamp, self.client_usage = clients, now, usage
        self.engine_load = {slot: round(min(100.0, max(loads.values(), default=0.0)), 1) for slot, loads in engines.items()} if usable else None

    def _sample_card(self, card: GpuCard) -> dict:
        if card.kind == "nvidia":
            with self.lock:
                reading = self.latest.get(card.slot)
            if card.slot in self.asleep:
                return {"id": card.slot, "name": (reading or {}).get("name") or card.name, "vendor": "nvidia", "integrated": False, "asleep": True, "util": None}
            return dict(reading or {"name": card.name, "vendor": "nvidia", "util": None}, id=card.slot, integrated=False)
        if card.kind == "intel":
            util = None if self.engine_load is None else self.engine_load.get(card.slot, 0.0)
        else:
            util = read_float(f"{card.device}/gpu_busy_percent")
        temp = self._hwmon_value(card.hwmon, "temp", ("edge", "junction"))
        power = self._hwmon_value(card.hwmon, "power", ("ppt", "power"))
        freq = self._hwmon_value(card.hwmon, "freq", ("sclk",))
        base = os.path.dirname(card.device)
        return {
            "id": card.slot, "name": card.name, "vendor": card.kind, "integrated": card.integrated, "util": util,
            "memUsed": read_float(f"{card.device}/mem_info_vram_used"),
            "memTotal": read_float(f"{card.device}/mem_info_vram_total"),
            "temp": temp / 1000 if temp else None,
            "power": power / 1_000_000 if power else None,
            "mhz": freq / 1_000_000 if freq else read_float(f"{base}/gt_cur_freq_mhz") or read_float(f"{base}/gt/gt0/rps_cur_freq_mhz"),
            "maxMhz": read_float(f"{base}/gt_max_freq_mhz") or read_float(f"{base}/gt_RP0_freq_mhz"),
            "fan": None,
        }

    def sample(self, slow: bool, processes: bool = False) -> list[dict]:
        if slow and (processes or any(card.kind == "intel" for card in self.cards)):
            self._sample_clients()
        if self._nvidia_gate() == "query":
            self._query_nvidia()
        return [self._sample_card(card) for card in self.cards]

    def processes(self) -> dict[str, list[dict]]:
        rows = [(slot, pid, process_name(pid), util, mem) for (slot, pid), (util, mem) in self.client_usage.items()]
        if self._nvidia_gate() != "rest":
            if self.nvidia_slots is None:
                self.nvidia_slots = {}
                for line in run(["nvidia-smi", "--query-gpu=index,pci.bus_id", "--format=csv,noheader"]).splitlines():
                    index, _, bus = line.partition(",")
                    if bus:
                        self.nvidia_slots[index.strip()] = normalize_slot(bus)
            for row in parse_pmon(run(["nvidia-smi", "pmon", "-c", "1", "-s", "um"]), self.nvidia_slots):
                name = process_name(row["pid"]) if os.path.exists(f"/proc/{row['pid']}") else row["name"]
                rows.append((row["slot"], row["pid"], name, row["util"], row["mem"]))
        groups: dict[str, dict[str, dict]] = {}
        for slot, pid, name, util, mem in rows:
            group = groups.setdefault(slot, {}).setdefault(name, {"name": name, "pid": pid, "count": 0, "util": 0.0, "mem": 0.0})
            group["count"] += 1
            group["util"] = min(100.0, group["util"] + util)
            group["mem"] += mem
        return {
            slot: [dict(group, util=round(group["util"], 1)) for group in sorted(
                (group for group in by_name.values() if group["util"] > 0 or group["mem"] > 0),
                key=lambda group: (-group["util"], -group["mem"], group["name"]))[:PROC_LIMIT]]
            for slot, by_name in groups.items()
        }

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            kill_process_group(self.proc)
            self.proc.wait()
        self.proc = None


def sample_memory() -> dict:
    info: dict[str, int] = {}
    for line in read_text("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts:
            info[key] = int(parts[0]) * 1024
    total = info.get("MemTotal", 0)
    free = info.get("MemFree", 0)
    available = info.get("MemAvailable", free)
    buffers = info.get("Buffers", 0)
    cached = info.get("Cached", 0) + info.get("SReclaimable", 0)
    shmem = info.get("Shmem", 0)
    swap_total = info.get("SwapTotal", 0)
    swap_used = swap_total - info.get("SwapFree", 0)
    apps = max(0, total - free - buffers - cached)
    zram_orig = 0
    zram_compr = 0
    for dev in bounded_directory_names("/sys/block"):
        if dev.startswith("zram"):
            fields = read_text(f"/sys/block/{dev}/mm_stat").split()
            if len(fields) >= 3:
                zram_orig += int(fields[0])
                zram_compr += int(fields[1])
    pressure_some, pressure_full = parse_pressure("memory")
    return {
        "total": total,
        "free": free,
        "available": available,
        "used": max(0, total - available),
        "apps": apps,
        "cached": max(0, cached + buffers - shmem),
        "shared": shmem,
        "swapTotal": swap_total,
        "swapUsed": max(0, swap_used),
        "compressed": zram_orig,
        "compressedSize": zram_compr,
        "pressureSome": pressure_some,
        "pressureFull": pressure_full,
    }


ZPOOL_VDEV_CLASSES = ("logs", "cache", "spare", "special", "dedup")


def zfs_pool(fstype: str, device: str) -> str | None:
    return device.split("/")[0] or None if fstype == "zfs" and "@" not in device else None


def parse_zfs_space(raw: str) -> dict[str, tuple[int, int]]:
    space: dict[str, tuple[int, int]] = {}
    for line in raw.splitlines():
        fields = line.split("\t")
        if len(fields) >= 3 and fields[0] and fields[1].isdigit() and fields[2].isdigit():
            space[bounded_text(fields[0], PATH_TEXT_LIMIT)] = (int(fields[1]), int(fields[2]))
    return space


def parse_zpool_leaves(raw: str) -> dict[str, str]:
    leaves: dict[str, str] = {}
    pool = None
    for line in raw.splitlines():
        name = line.strip()
        if not name:
            continue
        if name in ZPOOL_VDEV_CLASSES:
            pool = None
        elif not line[0].isspace():
            pool = name
        elif pool and name.startswith("/"):
            leaves.setdefault(pool, name)
    return leaves


def by_id_rank(link: str) -> int | None:
    if "-part" in link or link.startswith(("dm-", "md-", "lvm-")):
        return None
    if link.startswith(("nvme-eui.", "nvme-nvme.")):
        return BY_ID_BUS_RANK
    return next((rank for rank, prefix in enumerate(BY_ID_PREFIX_RANKS) if link.startswith(prefix)), BY_ID_FALLBACK_RANK)


def scan_disk_ids() -> dict[str, str]:
    best: dict[str, tuple[int, int, str]] = {}
    for link in bounded_directory_names("/dev/disk/by-id"):
        rank = by_id_rank(link)
        try:
            disk = os.path.basename(os.readlink(f"/dev/disk/by-id/{link}"))
        except OSError:
            continue
        candidate = (rank, len(link), bounded_text(link)) if rank is not None else None
        if candidate and (disk not in best or candidate < best[disk]):
            best[disk] = candidate
    return {disk: link for disk, (_, _, link) in best.items()}


def unescape_mount(raw: str) -> str:
    return re.sub(rb"\\([0-3][0-7]{2})", lambda match: bytes([int(match.group(1), 8)]), raw.encode()).decode("utf-8", "replace")


def parse_mountinfo(raw: str) -> list[dict]:
    mounts = []
    for line in raw.splitlines():
        head, separator, tail = line.partition(" - ")
        head_parts, tail_parts = head.split(" "), tail.split(" ")
        if not separator or len(head_parts) < 6 or len(tail_parts) < 2 or not head_parts[0].isdigit():
            continue
        mounts.append({
            "id": int(head_parts[0]),
            "mount": bounded_text(unescape_mount(head_parts[4]), PATH_TEXT_LIMIT),
            "fstype": bounded_text(tail_parts[0], FIELD_TEXT_LIMIT),
            "source": bounded_text(unescape_mount(tail_parts[1]), PATH_TEXT_LIMIT),
            "options": [option for option in head_parts[5].split(",") + (tail_parts[2] if len(tail_parts) > 2 else "").split(",") if option],
        })
    return mounts


def is_external(disk: str) -> bool:
    real = os.path.realpath(f"/sys/block/{disk}")
    if read_int(f"/sys/block/{disk}/removable", 0) == 1 or "/usb" in real:
        return True
    while real.startswith("/sys/devices/"):
        if read_text(f"{real}/removable") == "removable":
            return True
        real = os.path.dirname(real)
    return False


STUCK_MOUNTS: set[str] = set()


def statvfs_bounded(path: str):
    if path in STUCK_MOUNTS:
        return None
    result: list = []

    def probe() -> None:
        try:
            result.append(os.statvfs(path))
        except OSError:
            result.append(None)
        STUCK_MOUNTS.discard(path)

    STUCK_MOUNTS.add(path)
    thread = threading.Thread(target=probe, daemon=True)
    thread.start()
    thread.join(NETWORK_STATVFS_TIMEOUT)
    return result[0] if result else None


def dm_chain(device: str) -> list[tuple[str, str]]:
    name = os.path.basename(os.path.realpath(device))
    chain = []
    for _ in range(MAX_DEVICE_STACK_DEPTH):
        lower = next(iter(bounded_directory_names(f"/sys/block/{name}/slaves")), None) if name.startswith("dm-") else None
        if not lower:
            break
        chain.append((name, lower))
        name = lower
    return chain


def discard_max(name: str) -> int | None:
    value = read_int(f"/sys/block/{name}/queue/discard_max_bytes")
    return read_int(f"/sys/class/block/{name}/../queue/discard_max_bytes") if value is None else value


def device_uuid(device: str) -> str | None:
    real = os.path.realpath(device)
    return next((uuid for uuid in bounded_directory_names("/dev/disk/by-uuid") if os.path.realpath(f"/dev/disk/by-uuid/{uuid}") == real), None)


def plain_name(value: str | None) -> bool:
    return bool(value) and len(value) <= PLAIN_NAME_MAX_LENGTH and ".." not in value and re.fullmatch(r"[A-Za-z0-9._:/-]+", value) is not None


def volume_checks(volume: dict, options: list[str]) -> list[dict]:
    checks: list[dict] = []
    if volume["kind"] == "network":
        return checks
    for dm, lower in dm_chain(volume["device"]):
        if discard_max(dm) == 0 and discard_max(lower):
            name, uuid = read_text(f"/sys/block/{dm}/dm/name"), read_text(f"/sys/block/{dm}/dm/uuid")
            if uuid.startswith(LVM_DM_UUID_PREFIX):
                below = read_text(f"/sys/block/{lower}/dm/name")
                fixable = plain_name(below)
                checks.append({"id": "trim-stale", "layer": bounded_text(below or lower), "fix": "reload-volumes" if fixable else None, "args": [below] if fixable else []})
            elif uuid.startswith(CRYPT_DM_UUID_PREFIX):
                fixable = uuid.startswith(LUKS2_DM_UUID_PREFIX) and plain_name(name)
                checks.append({"id": "trim-blocked", "layer": bounded_text(name), "fix": "allow-discards" if fixable else None, "args": [name] if fixable else []})
            break
    slow = [flag for flag in FAT_SLOW_MOUNT_FLAGS if flag in options]
    if volume["fstype"] in ("vfat", "msdos") and slow:
        uuid = device_uuid(volume["device"])
        fixable = volume["mount"].startswith(UDISKS_MOUNT_ROOTS) and plain_name(uuid) and plain_name(volume["device"])
        checks.append({"id": "fat-flush", "flags": slow, "fix": "udisks-no-flush" if fixable else None, "args": [uuid, volume["device"]] if fixable else []})
    return checks


def parse_diskstats(parts: list[str]) -> tuple[int, int, int, int, int, int]:
    def field(index: int) -> int:
        return int(parts[index]) if index < len(parts) and parts[index].isdigit() else 0
    return (
        field(5) * SECTOR_BYTES,
        field(9) * SECTOR_BYTES,
        field(3) + field(7) + field(14) + field(18),
        field(6) + field(10) + field(17) + field(19),
        field(12),
        field(13),
        field(11),
    )


def disk_load(prev: tuple, now: tuple, elapsed: float) -> dict:
    requests = max(0, now[2] - prev[2])
    window = max(1.0, elapsed * 1000)
    return {
        "latency": round(max(0, now[3] - prev[3]) / requests, 2) if requests else None,
        "queue": round(max(0, now[5] - prev[5]) / window, 2),
        "busy": round(min(100.0, max(0, now[4] - prev[4]) / window * 100), 1),
    }


class DiskSampler:
    def __init__(self) -> None:
        self.prev: dict[str, tuple[int, int, int, int, int, int]] = {}
        self.ids: dict[str, str] = {}
        self.mount_keys: dict[int, str] = {}
        self.volumes_cache: list[dict] = []
        self.volumes_stamp = 0.0
        self.drive_temps: dict[str, str] = {}
        self._scan_drive_temps()

    def _scan_drive_temps(self) -> None:
        base = "/sys/class/hwmon"
        if not os.path.isdir(base):
            return
        for hw in bounded_directory_names(base):
            name = read_text(f"{base}/{hw}/name")
            if name not in ("nvme", "drivetemp"):
                continue
            device = f"{base}/{hw}/device"
            block = None
            try:
                for entry in bounded_directory_names(device):
                    if re.fullmatch(r"(nvme\d+n\d+|sd[a-z]+)", entry):
                        block = entry
                        break
                if block is None and os.path.isdir(f"{device}/block"):
                    block = next(iter(bounded_directory_names(f"{device}/block")), None)
                if block is None and os.path.isdir(f"{device}/nvme"):
                    ctrl = os.path.basename(os.path.realpath(device))
                    for entry in bounded_directory_names("/sys/block"):
                        if entry.startswith(ctrl):
                            block = entry
                            break
            except OSError:
                continue
            if block is None:
                ctrl = os.path.basename(os.path.realpath(device))
                for entry in bounded_directory_names("/sys/block"):
                    if entry.startswith(ctrl):
                        block = entry
                        break
            if block:
                self.drive_temps[block] = f"{base}/{hw}/temp1_input"

    @staticmethod
    def whole_disk_name(device: str) -> str:
        real = os.path.realpath(device)
        name = os.path.basename(real)
        for _ in range(MAX_DEVICE_STACK_DEPTH):
            slaves = f"/sys/block/{name}/slaves"
            if os.path.isdir(slaves):
                entries = bounded_directory_names(slaves)
                if entries:
                    name = entries[0]
                    continue
            break
        if os.path.isdir(f"/sys/block/{name}"):
            return name
        match = re.match(r"(nvme\d+n\d+)p\d+$", name) or re.match(r"(mmcblk\d+)p\d+$", name) or re.match(r"([a-z]+)\d+$", name)
        if match and os.path.isdir(f"/sys/block/{match.group(1)}"):
            return match.group(1)
        for disk in bounded_directory_names("/sys/block"):
            if os.path.isdir(f"/sys/block/{disk}/{name}"):
                return disk
        return name

    def _volumes(self) -> list[dict]:
        volumes: dict[str, dict] = {}
        options: dict[str, list[str]] = {}
        mount_keys: dict[int, str] = {}
        mounts = parse_mountinfo(read_text("/proc/self/mountinfo"))
        zfs_space: dict[str, tuple[int, int]] = {}
        zfs_leaves: dict[str, str] = {}
        if any(zfs_pool(mount["fstype"], mount["source"]) for mount in mounts):
            zfs_space = parse_zfs_space(run(["zfs", "list", "-Hp", "-d", "0", "-o", "name,used,avail"]))
            zfs_leaves = parse_zpool_leaves(run(["zpool", "list", "-HPv", "-o", "name"]))
        drives: dict[str, tuple[str, bool, bool, bool]] = {}
        for entry in mounts:
            device, mount, fstype = entry["source"], entry["mount"], entry["fstype"]
            network = fstype in NETWORK_FS
            pool = zfs_pool(fstype, device)
            if fstype not in REAL_FS and not network:
                continue
            if not device or (pool is None and not network and not device.startswith("/")):
                continue
            if mount.startswith(("/proc", "/sys", "/dev", "/run/user", "/var/lib/docker", "/snap")):
                continue
            device = pool or device
            if network:
                disk = ""
            elif pool is None:
                disk = self.whole_disk_name(device)
            else:
                disk = self.whole_disk_name(zfs_leaves[pool]) if pool in zfs_leaves else ""
            key = disk or device
            mount_keys[entry["id"]] = key
            existing = volumes.get(device)
            if (existing and len(existing["mount"]) <= len(mount)) or (existing is None and len(volumes) >= VOLUME_LIMIT):
                continue
            try:
                stat = statvfs_bounded(mount) if network else os.statvfs(mount)
            except OSError:
                stat = None
            if stat is None:
                continue
            size = stat.f_blocks * stat.f_frsize
            avail = stat.f_bavail * stat.f_frsize
            used = size - stat.f_bfree * stat.f_frsize
            if pool in zfs_space:
                used, avail = zfs_space[pool]
                size = used + avail
            if size < MIN_VOLUME_BYTES:
                continue
            if disk not in drives:
                model = read_text(f"/sys/block/{disk}/device/model") or read_text(f"/sys/block/{disk}/device/name") if disk else ""
                drives[disk] = (
                    re.sub(r"\s+", " ", bounded_text(model)).strip(),
                    bool(disk) and read_int(f"/sys/block/{disk}/queue/rotational", 0) == 1,
                    bool(disk) and read_int(f"/sys/block/{disk}/removable", 0) == 1,
                    bool(disk) and is_external(disk),
                )
            model, rotational, removable, external = drives[disk]
            options[device] = entry["options"]
            volumes[device] = {
                "mount": mount, "device": device, "fstype": fstype,
                "size": size, "used": used, "avail": avail,
                "disk": disk, "key": key,
                "kind": "network" if network else ("external" if external else "internal"),
                "model": model, "rotational": rotational, "removable": removable,
            }
        for volume in volumes.values():
            volume["checks"] = volume_checks(volume, options.get(volume["device"], []))
        self.mount_keys = mount_keys
        return sorted(volumes.values(), key=lambda volume: (volume["mount"] != "/", volume["mount"]))

    def sample(self, elapsed: float, now: float) -> dict:
        if now - self.volumes_stamp > VOLUMES_REFRESH_SECONDS:
            self.volumes_cache = self._volumes()
            self.volumes_stamp = now
        current: dict[str, tuple[int, int, int, int, int, int]] = {}
        for line in read_text("/proc/diskstats").splitlines():
            parts = line.split()
            if len(parts) < 14:
                continue
            name = parts[2]
            if not re.fullmatch(r"(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|hd[a-z]+|mmcblk\d+|xvd[a-z]+)", name):
                continue
            if (read_int(f"/sys/block/{name}/size", 0) or 0) <= 0:
                continue
            current[name] = parse_diskstats(parts)
        if current.keys() != self.prev.keys():
            self.ids = scan_disk_ids()
        per_disk: dict[str, dict] = {}
        total_read = 0.0
        total_write = 0.0
        for name, counters in current.items():
            prev = self.prev.get(name)
            read_rate = rate(counters[0], prev[0] if prev else None, elapsed)
            write_rate = rate(counters[1], prev[1] if prev else None, elapsed)
            temp_path = self.drive_temps.get(name)
            temp = read_int(temp_path) if temp_path else None
            per_disk[name] = {
                "id": self.ids.get(name, name),
                "read": read_rate,
                "write": write_rate,
                "temp": round(temp / 1000, 1) if temp else None,
                "inFlight": counters[6],
                **(disk_load(prev, counters, elapsed) if prev else {"latency": None, "queue": None, "busy": None}),
            }
            total_read += read_rate
            total_write += write_rate
        self.prev = current
        volumes = [dict(volume, temp=per_disk.get(volume["disk"], {}).get("temp")) for volume in self.volumes_cache]
        pressure_some, pressure_full = parse_pressure("io")
        return {
            "volumes": volumes,
            "read": total_read,
            "write": total_write,
            "perDisk": per_disk,
            "pressureSome": pressure_some,
            "pressureFull": pressure_full,
        }


class NetworkSampler:
    def __init__(self) -> None:
        self.prev: dict[str, tuple[int, int]] = {}
        self.addr_cache: dict[str, dict] = {}
        self.default_iface = ""
        self.routing_changed = threading.Event()
        self.routing_changed.set()
        threading.Thread(target=self._watch_routing, daemon=True).start()
        self.wifi_cache: dict[str, dict] = {}
        self.wifi_stamp = 0.0
        self.public_ip = ""
        self.public_stamp = 0.0
        self.public_lock = threading.Lock()
        self.public_inflight = False

    def _watch_routing(self) -> None:
        events = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
        events.bind((0, ROUTING_EVENT_GROUPS))
        while True:
            try:
                events.recv(NETLINK_RECEIVE_BYTES)
            except OSError as error:
                if error.errno != errno.ENOBUFS:
                    raise
            self.routing_changed.set()

    @staticmethod
    def _default_iface() -> str:
        for line in read_text("/proc/net/route").splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 4 and parts[1] == "00000000" and int(parts[3], 16) & 2:
                return parts[0]
        for line in read_text("/proc/net/ipv6_route").splitlines():
            parts = line.split()
            if len(parts) >= 10 and parts[0] == "0" * 32 and parts[1] == "00":
                return parts[9]
        return ""

    def _refresh_addresses(self) -> None:
        self.addr_cache = {}
        if not trusted_helper_path("ip"):
            return
        try:
            data = json.loads(run(["ip", "-j", "addr"]) or "[]")
        except json.JSONDecodeError:
            return
        for iface in data:
            name = bounded_text(str(iface.get("ifname", "")))
            if not name:
                continue
            v4, v6 = [], []
            for addr in iface.get("addr_info", []):
                if addr.get("scope") != "global":
                    continue
                if addr.get("family") == "inet":
                    v4.append(bounded_text(str(addr.get("local", "")), FIELD_TEXT_LIMIT))
                elif addr.get("family") == "inet6" and not addr.get("temporary"):
                    v6.append(bounded_text(str(addr.get("local", "")), FIELD_TEXT_LIMIT))
            self.addr_cache[name] = {"ipv4": v4, "ipv6": v6}

    def _refresh_wifi(self, ifaces: list[str]) -> None:
        self.wifi_cache = {}
        if not trusted_helper_path("iw"):
            return
        for name in ifaces:
            info: dict = {}
            for line in run(["iw", "dev", name, "link"]).splitlines():
                line = line.strip()
                if line.startswith("SSID:"):
                    info["ssid"] = bounded_text(line[5:].strip(), SSID_TEXT_LIMIT)
                elif line.startswith("signal:"):
                    match = re.search(r"(-?\d+) dBm", line)
                    if match:
                        info["dbm"] = int(match.group(1))
                elif line.startswith("freq:"):
                    match = re.search(r"([0-9.]+)", line)
                    if match:
                        info["freq"] = float(match.group(1))
                elif line.startswith("tx bitrate:"):
                    match = re.search(r"([0-9.]+) MBit/s", line)
                    if match:
                        info["bitrate"] = float(match.group(1))
            self.wifi_cache[name] = info

    def fetch_public_ip(self) -> None:
        with self.public_lock:
            if self.public_inflight:
                return
            self.public_inflight = True

        def worker() -> None:
            result = ""
            for url in ("https://api.ipify.org", "https://icanhazip.com", "https://ifconfig.me/ip"):
                try:
                    with urllib.request.urlopen(url, timeout=5) as response:
                        raw = response.read(FIELD_TEXT_LIMIT + 1)
                        candidate = raw.decode("utf-8", "replace").strip()
                    if len(raw) <= FIELD_TEXT_LIMIT and re.fullmatch(r"[0-9a-fA-F.:]+", candidate):
                        result = candidate
                        break
                except Exception:
                    continue
            with self.public_lock:
                self.public_ip = result
                self.public_stamp = time.time()
                self.public_inflight = False

        threading.Thread(target=worker, daemon=True).start()

    def sample(self, elapsed: float, now: float, detail: bool) -> dict:
        current: dict[str, tuple[int, int]] = {}
        for line in read_text("/proc/net/dev").splitlines()[2:]:
            name, _, rest = line.partition(":")
            name = name.strip()
            parts = rest.split()
            if name == "lo" or len(parts) < 16:
                continue
            current[name] = (int(parts[0]), int(parts[8]))
        refresh_seconds = DETAIL_REFRESH_SECONDS if detail else IDLE_REFRESH_SECONDS
        if self.routing_changed.is_set():
            self.routing_changed.clear()
            self._refresh_addresses()
            self.default_iface = self._default_iface()
        wireless = [n for n in current if os.path.isdir(f"/sys/class/net/{n}/wireless")]
        if wireless and now - self.wifi_stamp > refresh_seconds:
            self._refresh_wifi(wireless)
            self.wifi_stamp = now
        default = self.default_iface
        ifaces = []
        total_rx = total_tx = 0.0
        default_rx = default_tx = 0.0
        online = False
        for name, (rx_total, tx_total) in current.items():
            prev = self.prev.get(name)
            rx = rate(rx_total, prev[0] if prev else None, elapsed)
            tx = rate(tx_total, prev[1] if prev else None, elapsed)
            state = read_text(f"/sys/class/net/{name}/operstate")
            up = state == "up" or (state == "unknown" and rx_total > 0)
            if name.startswith(("veth", "docker", "br-", "virbr", "vmnet", "tap")) and name != default:
                continue
            speed = read_int(f"/sys/class/net/{name}/speed", 0) or 0
            addrs = self.addr_cache.get(name, {"ipv4": [], "ipv6": []})
            entry = {
                "name": name,
                "up": up,
                "default": name == default,
                "wireless": name in wireless,
                "speed": speed if speed > 0 else 0,
                "rx": rx,
                "tx": tx,
                "rxTotal": rx_total,
                "txTotal": tx_total,
                "ipv4": addrs["ipv4"],
                "ipv6": addrs["ipv6"],
            }
            entry.update(self.wifi_cache.get(name, {}))
            ifaces.append(entry)
            if up:
                total_rx += rx
                total_tx += tx
            if name == default:
                default_rx, default_tx = rx, tx
                online = up
        self.prev = current
        ifaces.sort(key=lambda i: (not i["default"], not i["up"], i["name"]))
        with self.public_lock:
            public_ip = self.public_ip
        return {
            "ifaces": ifaces,
            "default": default,
            "rx": default_rx if default else total_rx,
            "tx": default_tx if default else total_tx,
            "online": online or any(i["up"] for i in ifaces),
            "publicIp": public_ip,
        }


class SensorSampler:
    def __init__(self) -> None:
        self.chips: list[dict] = []
        self.stamp = 0.0
        self.gpu_temp_path: str | None = None

    def _scan(self) -> None:
        base = "/sys/class/hwmon"
        chips: list[dict] = []
        remaining = 1024
        if not os.path.isdir(base):
            self.chips = []
            return
        for hw in sorted(bounded_directory_names(base), key=lambda h: int(h[5:]) if h[5:].isdigit() else 0):
            if remaining == 0:
                break
            path = f"{base}/{hw}"
            name = bounded_text(read_text(f"{path}/name"))
            if not name:
                continue
            temps, fans = [], []
            for entry in bounded_directory_names(path):
                if len(temps) + len(fans) >= remaining:
                    break
                if entry.startswith("temp") and entry.endswith("_input"):
                    key = entry[:-6]
                    maximum = read_int(f"{path}/{key}_max")
                    critical = read_int(f"{path}/{key}_crit")
                    temps.append({
                        "key": key,
                        "label": bounded_text(read_text(f"{path}/{key}_label")),
                        "path": f"{path}/{entry}",
                        "max": maximum or critical or 0,
                        "critical": critical or maximum or 0,
                    })
                elif entry.startswith("fan") and entry.endswith("_input"):
                    key = entry[:-6]
                    fans.append({
                        "key": key,
                        "label": bounded_text(read_text(f"{path}/{key}_label")),
                        "path": f"{path}/{entry}",
                    })
            if not temps and not fans:
                continue
            remaining -= len(temps) + len(fans)
            device_link = f"{path}/device"
            device_id = (os.path.realpath(device_link) if os.path.exists(device_link)
                         else os.path.dirname(os.path.dirname(os.path.realpath(path))))
            device_name = os.path.basename(device_id) if os.path.exists(device_link) else ""
            if re.fullmatch(r"nvme\d+", device_name):
                device_name = os.path.basename(os.path.dirname(os.path.dirname(device_id)))
            chips.append({"name": name, "path": path, "temps": temps, "fans": fans,
                          "device_id": device_id, "device": bounded_text(device_name),
                          "labelled": any(t["label"] for t in temps) or any(f["label"] for f in fans)})
        self.chips = self.deduplicate_sensor_channels(chips)
        self.gpu_temp_path = None
        for chip in self.chips:
            if chip["name"] in GPU_TEMP_HWMON and chip["temps"]:
                preferred = [t for t in chip["temps"] if t["label"].lower() in ("edge", "junction")]
                self.gpu_temp_path = (preferred or chip["temps"])[0]["path"]
                break

    @staticmethod
    def _is_board_chip(name: str) -> bool:
        return name.startswith(("nct", "it87", "f71", "w83", "asus_ec"))

    @staticmethod
    def _score(chip: dict) -> int:
        return sum(2 for f in chip["fans"] if f["label"]) + sum(1 for t in chip["temps"] if t["label"])

    def deduplicate_sensor_channels(self, chips: list[dict]) -> list[dict]:
        kept: list[dict] = []
        for chip in chips:
            duplicate = None
            if self._is_board_chip(chip["name"]):
                duplicate = next((other for other in kept if other["name"] == chip["name"]), None)
            if duplicate is None:
                kept.append(chip)
            elif self._score(chip) > self._score(duplicate):
                kept[kept.index(duplicate)] = chip
        return kept

    @staticmethod
    def _pretty_chip(name: str) -> str:
        table = {
            "k10temp": "CPU", "zenpower": "CPU", "coretemp": "CPU", "nvme": "NVMe",
            "drivetemp": "Drive", "amdgpu": "GPU", "nouveau": "GPU", "i915": "GPU",
            "acpitz": "ACPI", "iwlwifi_1": "Wi-Fi", "mt7921_phy0": "Wi-Fi",
            "spd5118": "Memory", "jc42": "Memory", "thinkpad": "ThinkPad",
            "BAT0": "Battery", "BAT1": "Battery",
        }
        if name in table:
            return table[name]
        if name.startswith("r8169") or name.startswith("igc") or name.startswith("e1000"):
            return "Ethernet"
        if name.startswith("mt79") or name.startswith("iwl") or name.startswith("ath"):
            return "Wi-Fi"
        if name.startswith("nct") or name.startswith("it87") or name.startswith("f71"):
            return "Board"
        return bounded_text(name)

    def sample(self, now: float) -> dict:
        if now - self.stamp > SENSOR_RESCAN_SECONDS:
            self._scan()
            self.stamp = now
        temps, fans = [], []
        siblings: dict[str, list[str]] = {}
        for chip in self.chips:
            siblings.setdefault(chip["name"], []).append(chip["device"])
        for devices in siblings.values():
            devices.sort()
        for chip in self.chips:
            chip_label = self._pretty_chip(chip["name"])
            shared = len(siblings[chip["name"]]) > 1
            prefix = f"{chip['name']}@{chip['device']}" if shared and chip["device"] else chip["name"]
            if shared:
                chip_label = f"{chip_label} {siblings[chip['name']].index(chip['device']) + 1}"
            for temp in chip["temps"]:
                raw = read_int(temp["path"])
                if raw is None or raw <= 0 or raw >= MAX_PLAUSIBLE_MILLIDEGREES:
                    continue
                label = temp["label"] or (chip_label if len(chip["temps"]) == 1 else f"{chip_label} {temp['key'][4:]}")
                temps.append({
                    "chip": chip_label,
                    "id": f"{prefix}/{temp['key']}",
                    "alertId": f"{chip['name']}|{chip['device_id']}|{temp['key']}",
                    "label": label,
                    "value": round(raw / 1000, 1),
                    "max": round(temp["max"] / 1000) if 0 < temp["max"] < 200_000 else 0,
                    "critical": round(temp["critical"] / 1000) if 0 < temp["critical"] < 200_000 else 0,
                })
            for fan in chip["fans"]:
                raw = read_int(fan["path"])
                if raw is None:
                    continue
                fans.append({
                    "chip": chip_label,
                    "id": f"{prefix}/{fan['key']}",
                    "label": fan["label"] or f"Fan {fan['key'][3:]}",
                    "rpm": raw,
                })
        gpu_temp = None
        if self.gpu_temp_path:
            raw = read_int(self.gpu_temp_path)
            if raw:
                gpu_temp = round(raw / 1000, 1)
        return {"temps": temps, "fans": fans, "gpuTemp": gpu_temp}


class BatterySampler:
    def __init__(self) -> None:
        self.entries: list[str] | None = None
        self.mains: list[str] = []
        self.peripherals: list[tuple[str, str]] = []
        self.system: tuple[str, str, str] | None = None

    def _discover(self, entries: list[str]) -> None:
        self.entries = entries
        self.mains, self.peripherals, self.system = [], [], None
        for entry in entries:
            path = f"{POWER_SUPPLY_DIR}/{entry}"
            ptype = read_text(f"{path}/type")
            if ptype in MAINS_SUPPLY_TYPES:
                self.mains.append(path)
                continue
            if ptype != "Battery":
                continue
            model = bounded_text(read_text(f"{path}/model_name"))
            if read_text(f"{path}/scope") == "Device" or entry.startswith(("hid", "wacom")) or (not entry.startswith("BAT") and read_int(f"{path}/present", 1) == 1 and read_int(f"{path}/energy_full") is None and read_int(f"{path}/charge_full") is None):
                self.peripherals.append((path, model or bounded_text(entry)))
            elif self.system is None:
                self.system = (entry, model, bounded_text(read_text(f"{path}/technology")))

    def sample(self) -> dict | None:
        if os.environ.get("SYSTEMSTATS_FAKE_BATTERY"):
            phase = (time.time() / 4) % 100
            return {
                "present": True, "name": "BAT0", "percent": round(35 + phase / 2, 1),
                "status": "Charging" if int(time.time() / 40) % 2 else "Discharging",
                "energyNow": 32.1, "energyFull": 56.0, "energyDesign": 57.0, "power": 12.4,
                "voltage": 11.9, "timeToEmpty": 142, "timeToFull": 0, "cycles": 212,
                "health": 98.2, "acOnline": bool(int(time.time() / 40) % 2), "model": "Demo Cell",
                "peripherals": [{"name": "MX Master 3S", "percent": 70, "status": "Discharging"}],
            }
        entries = bounded_directory_names(POWER_SUPPLY_DIR)
        if entries != self.entries:
            self._discover(entries)
        ac_online = None
        for path in self.mains:
            online = read_int(f"{path}/online")
            if online is not None:
                ac_online = bool(online) if ac_online is None else (ac_online or bool(online))
        peripherals = []
        for path, name in self.peripherals:
            capacity = read_int(f"{path}/capacity")
            if capacity is not None and len(peripherals) < PERIPHERAL_LIMIT:
                peripherals.append({"name": name, "percent": capacity, "status": bounded_text(read_text(f"{path}/status") or "Unknown")})
        if self.system is None:
            return {"present": False, "peripherals": peripherals} if peripherals else None
        entry, model, technology = self.system
        path = f"{POWER_SUPPLY_DIR}/{entry}"
        capacity = read_int(f"{path}/capacity")
        status = bounded_text(read_text(f"{path}/status") or "Unknown")
        present = read_int(f"{path}/present", 1) == 1
        voltage = (read_int(f"{path}/voltage_now") or 0) / 1_000_000
        energy_now = read_int(f"{path}/energy_now")
        energy_full = read_int(f"{path}/energy_full")
        energy_design = read_int(f"{path}/energy_full_design")
        power_now = read_int(f"{path}/power_now")
        if energy_now is None:
            charge_now = read_int(f"{path}/charge_now")
            charge_full = read_int(f"{path}/charge_full")
            charge_design = read_int(f"{path}/charge_full_design")
            current_now = read_int(f"{path}/current_now")
            energy_now = charge_now * voltage if charge_now is not None else None
            energy_full = charge_full * voltage if charge_full is not None else None
            energy_design = charge_design * voltage if charge_design is not None else None
            power_now = abs(current_now) * voltage if current_now is not None else None
        health = None
        if energy_full and energy_design:
            health = round(min(100.0, energy_full / energy_design * 100), 1)
        power_w = (power_now or 0) / 1_000_000
        time_to_empty = read_int(f"{path}/time_to_empty_now")
        time_to_full = read_int(f"{path}/time_to_full_now")
        if time_to_empty is None and status == "Discharging" and power_w > 0 and energy_now:
            time_to_empty = round(energy_now / 1_000_000 / power_w * 60)
        if time_to_full is None and status == "Charging" and power_w > 0 and energy_now is not None and energy_full:
            time_to_full = round((energy_full - energy_now) / 1_000_000 / power_w * 60)
        if capacity is None and energy_now is not None and energy_full:
            capacity = round(energy_now / energy_full * 100)
        system = {
            "present": present,
            "name": entry,
            "percent": capacity,
            "status": status,
            "energyNow": round((energy_now or 0) / 1_000_000, 2),
            "energyFull": round((energy_full or 0) / 1_000_000, 2),
            "energyDesign": round((energy_design or 0) / 1_000_000, 2),
            "power": round(power_w, 2),
            "voltage": round(voltage, 2),
            "timeToEmpty": time_to_empty or 0,
            "timeToFull": time_to_full or 0,
            "cycles": read_int(f"{path}/cycle_count") or 0,
            "health": health,
            "acOnline": ac_online,
            "model": model,
            "technology": technology,
        }
        if system["acOnline"] is None:
            system["acOnline"] = system["status"] in ("Charging", "Full", "Not charging")
        system["peripherals"] = peripherals
        return system


def display_name(pid: int, comm: str) -> str:
    if len(comm) < KERNEL_COMM_LENGTH:
        return bounded_text(comm)
    cmdline = read_text(f"/proc/{pid}/cmdline").split("\0")[0]
    if cmdline:
        base = os.path.basename(cmdline)
        if base.startswith(comm[:8]) or len(base) > len(comm):
            return bounded_text(base)
    return bounded_text(comm)


class ProcessSampler:
    def __init__(self) -> None:
        self.prev: dict[int, tuple[int, int, int | None, int | None]] = {}
        self.io_primed = False
        self.threads = os.cpu_count() or 1
        self.uid = os.getuid()
        self.names: dict[int, str] = {}
        self.sockets_prev: dict[str, tuple[int, int]] = {}
        self.sockets_time: float | None = None

    def reset(self) -> None:
        self.prev = {}
        self.io_primed = False
        self.names = {}

    @staticmethod
    def open_mounts(pid: int) -> set[int]:
        mounts: set[int] = set()
        for fd in bounded_directory_names(f"/proc/{pid}/fdinfo", FD_SCAN_LIMIT)[:DRIVE_FD_LIMIT]:
            match = re.search(r"^mnt_id:\s*(\d+)", read_text(f"/proc/{pid}/fdinfo/{fd}"), re.M)
            if match:
                mounts.add(int(match.group(1)))
        return mounts

    def sample(self, elapsed: float, full: bool = False, drives: dict[int, str] | None = None) -> dict:
        current: dict[int, tuple[int, int, int | None, int | None]] = {}
        by_name: dict[str, dict] = {}
        names: dict[int, str] = {}
        for entry in bounded_directory_names("/proc", PROCESS_SCAN_LIMIT):
            if not entry.isdigit():
                continue
            pid = int(entry)
            raw_stat = read_raw(f"/proc/{pid}/stat", PROC_FILE_LIMIT)
            if raw_stat is None:
                continue
            stat = raw_stat.decode("utf-8", "replace")
            close = stat.rfind(")")
            open_paren = stat.find("(")
            if close < 0 or open_paren < 0:
                continue
            comm = stat[open_paren + 1:close]
            fields = stat[close + 2:].split()
            if len(fields) < 22:
                continue
            if fields[0] == "Z":
                continue
            ticks = int(fields[11]) + int(fields[12])
            rss = int(fields[21]) * PAGE_SIZE
            io_counters = read_raw(f"/proc/{pid}/io", PROC_FILE_LIMIT) if drives is not None else None
            read_bytes = write_bytes = None
            for line in (io_counters or b"").splitlines():
                if line.startswith(b"read_bytes:"):
                    read_bytes = int(line.split()[1])
                elif line.startswith(b"write_bytes:"):
                    write_bytes = int(line.split()[1])
                    break
            current[pid] = (ticks, rss, read_bytes, write_bytes)
            prev = self.prev.get(pid)
            cpu = 0.0
            io_read = io_write = 0.0
            if prev is not None and elapsed > 0:
                cpu = (ticks - prev[0]) / CLK_TCK / elapsed * 100 / self.threads
                io_read = rate(read_bytes, prev[2], elapsed)
                io_write = rate(write_bytes, prev[3], elapsed)
            name = self.names.get(pid) or display_name(pid, comm)
            names[pid] = name
            agg = by_name.get(name)
            if agg is None:
                agg = by_name[name] = {"name": name, "pid": pid, "cpu": 0.0, "mem": 0, "read": 0.0, "write": 0.0, "count": 0, "drives": set()}
            if drives is not None and io_read + io_write > 0:
                agg["drives"].update(drives[mount] for mount in self.open_mounts(pid) if mount in drives)
            agg["cpu"] += max(0.0, cpu)
            agg["mem"] += rss
            agg["read"] += io_read
            agg["write"] += io_write
            agg["count"] += 1
        self.prev = current
        self.io_primed = drives is not None
        self.names = names
        groups = list(by_name.values())

        def row(item: dict) -> dict:
            return {
                "name": item["name"], "pid": item["pid"], "count": item["count"],
                "cpu": round(item["cpu"], 1), "mem": item["mem"],
                "read": item["read"], "write": item["write"],
            }

        def trim(items: list[dict], key: str) -> list[dict]:
            return [row(item) for item in itertools.takewhile(lambda item: item[key] > 0, items[:PROC_LIMIT])]

        by_io = [group for group in sorted(groups, key=lambda group: group["read"] + group["write"], reverse=True) if group["read"] + group["write"] > 0]

        by_cpu = sorted(groups, key=lambda g: g["cpu"], reverse=True)
        result = {
            "cpu": trim(by_cpu, "cpu"),
            "mem": trim(sorted(groups, key=lambda g: g["mem"], reverse=True), "mem"),
            "total": len(groups),
            "io": [row(group) for group in by_io[:PROC_LIMIT]] if drives is not None else None,
        }
        if drives is not None:
            by_drive: dict[str, list[dict]] = {}
            for group in by_io:
                for drive in group["drives"]:
                    rows = by_drive.setdefault(drive, [])
                    if len(rows) < PROC_LIMIT:
                        rows.append(row(group))
            result["ioByDrive"] = by_drive
        if full:
            result["all"] = [row(group) for group in by_cpu[:FULL_LIMIT]]
        return result

    def network_usage(self, full: bool = False) -> list[dict]:
        sockets: dict[str, dict] = {}
        current: dict | None = None
        for line in run(["ss", "-tineH"]).splitlines():
            if line.startswith((" ", "\t")):
                if current is not None:
                    for tok in line.split():
                        if tok.startswith("bytes_sent:"):
                            current["sent"] = int(tok[11:] or 0)
                        elif tok.startswith("bytes_received:"):
                            current["recv"] = int(tok[15:] or 0)
                continue
            ino = ""
            cgroup = ""
            for tok in line.split():
                if tok.startswith("ino:"):
                    ino = tok[4:]
                elif tok.startswith("cgroup:"):
                    cgroup = tok[7:]
            current = None
            if ino:
                current = {"sent": 0, "recv": 0, "cgroup": cgroup, "established": line.startswith("ESTAB")}
                sockets[ino] = current
                if len(sockets) > SOCKET_SCAN_LIMIT:
                    self.sockets_prev = {}
                    self.sockets_time = None
                    return []
        if not sockets:
            self.sockets_prev = {}
            self.sockets_time = None
            return []

        owner: dict[str, tuple[int, str]] = {}
        for entry in bounded_directory_names("/proc", PROCESS_SCAN_LIMIT):
            if not entry.isdigit():
                continue
            pid = int(entry)
            name: str | None = None
            for _, target in fd_targets(entry):
                if not target.startswith("socket:["):
                    continue
                ino = target[8:-1]
                if ino not in sockets:
                    continue
                if name is None:
                    name = self.names.get(pid) or process_name(pid)
                owner[ino] = (pid, name)

        now = time.monotonic()
        elapsed = now - self.sockets_time if self.sockets_time is not None else 0.0
        usable = 0.0 < elapsed < MAX_RATE_GAP_SECONDS
        groups: dict[str, dict] = {}
        for ino, sock in sockets.items():
            pid, name = owner.get(ino, (0, cgroup_label(sock["cgroup"])))
            group = groups.setdefault(name, {"name": name, "pid": pid, "pids": set(), "connections": 0, "rx": 0.0, "tx": 0.0})
            group["pids"].add(pid)
            if sock["established"]:
                group["connections"] += 1
            prev = self.sockets_prev.get(ino)
            if usable and prev is not None:
                group["tx"] += max(0, sock["sent"] - prev[0]) / elapsed
                group["rx"] += max(0, sock["recv"] - prev[1]) / elapsed
        self.sockets_prev = {ino: (s["sent"], s["recv"]) for ino, s in sockets.items()}
        self.sockets_time = now

        ranked = sorted(
            (g for g in groups.values() if g["connections"] > 0 or g["rx"] + g["tx"] > 0),
            key=lambda g: (-(g["rx"] + g["tx"]), -g["connections"], g["name"]),
        )
        return [
            {"name": g["name"], "pid": g["pid"], "count": len(g["pids"]), "connections": g["connections"], "rx": g["rx"], "tx": g["tx"]}
            for g in ranked[: FULL_LIMIT if full else CONNECTION_LIMIT]
        ]


def cgroup_label(cgroup: str) -> str:
    last = cgroup.rsplit("/", 1)[-1].replace("\\x2d", "-")
    if not last:
        return "other"
    stem = last
    for suffix in (".scope", ".service", ".mount", ".slice"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    if stem.startswith("app-"):
        parts = stem[4:].split("-")
        if len(parts) >= 3:
            return bounded_text("-".join(parts[1:-1]))
        if len(parts) == 2:
            return bounded_text(parts[1])
    return bounded_text(stem) or "other"


class Controller:
    def __init__(self, interval: float) -> None:
        self.interval = interval
        self.detail = DETAIL_NONE
        self.focus = ""
        self.lock = threading.Lock()
        self.public_ip_requested = False
        self.stop = False
        self.wake = threading.Event()

    def pause(self, seconds: float) -> None:
        self.wake.wait(seconds)
        self.wake.clear()

    def listen(self) -> None:
        for line in bounded_lines(sys.stdin.buffer, CONTROL_LINE_LIMIT):
            parts = line.strip().split()
            if not parts:
                continue
            with self.lock:
                if parts[0] == "detail" and len(parts) > 1:
                    self.detail = DETAIL_ALL_PROCESSES if parts[1] in ("2", "full", "all") else (DETAIL_TOP_PROCESSES if parts[1] in ("1", "true", "on") else DETAIL_NONE)
                elif parts[0] == "focus" and len(parts) > 1:
                    self.focus = parts[1]
                elif parts[0] == "interval" and len(parts) > 1:
                    try:
                        self.interval = max(MIN_INTERVAL_SECONDS, min(MAX_INTERVAL_SECONDS, float(parts[1])))
                    except ValueError:
                        pass
                elif parts[0] == "pubip":
                    self.public_ip_requested = True
                elif parts[0] == "quit":
                    self.stop = True
                else:
                    continue
            self.wake.set()
            if self.stop:
                return


def main() -> int:
    interval = 1.0
    args = sys.argv[1:]
    if "--version" in args or "-V" in args:
        print("systemstats-sampler 1.0.0")
        return 0
    if "--interval" in args:
        try:
            interval = float(args[args.index("--interval") + 1])
        except (IndexError, ValueError):
            pass
    detail_flag = DETAIL_ALL_PROCESSES if "--full" in args else (DETAIL_TOP_PROCESSES if "--detail" in args else DETAIL_NONE)
    once = "--once" in args

    controller = Controller(interval)
    controller.detail = detail_flag
    if "--focus" in args:
        try:
            controller.focus = args[args.index("--focus") + 1]
        except IndexError:
            pass
    if not once:
        threading.Thread(target=controller.listen, daemon=True).start()

    cpu = CpuSampler()
    power = RaplSampler()
    gpu = GpuSampler()
    disks = DiskSampler()
    net = NetworkSampler()
    sensors = SensorSampler()
    battery = BatterySampler()
    procs = ProcessSampler()

    last = time.monotonic()
    seq = 0
    cpu.sample()
    gpu.sample(True)
    disks.sample(1.0, time.time())
    net.sample(1.0, time.time(), controller.detail != DETAIL_NONE)
    if controller.detail != DETAIL_NONE:
        procs.sample(1.0, controller.detail == DETAIL_ALL_PROCESSES)
    controller.pause(min(interval, 1.0) if not once else 0.5)

    last_slow: float | None = None
    last_procs: float | None = None
    sensors_cache: dict | None = None
    battery_cache: dict | None = None
    procs_cache: dict | None = None
    connections_cache: list | None = None
    gpu_procs_cache: dict | None = None
    network_primed = False

    while not controller.stop:
        with controller.lock:
            detail = controller.detail
            focus = controller.focus
            want_public = controller.public_ip_requested
            controller.public_ip_requested = False
            current_interval = controller.interval
        want_network = detail != DETAIL_NONE and focus == "network"
        want_gpu = detail != DETAIL_NONE and focus == "gpu"
        io_drives = disks.mount_keys if detail != DETAIL_NONE and focus == "disks" else None
        cold_procs = detail != DETAIL_NONE and (last_procs is None or io_drives is not None and not procs.io_primed)
        cold_network = want_network and not network_primed
        if cold_procs or cold_network:
            if cold_procs:
                procs.sample(1.0, False, io_drives)
                last_procs = time.monotonic()
            if cold_network:
                procs.network_usage(False)
                network_primed = True
            last_slow = None
            controller.pause(PROCESS_WARM_UP_SECONDS)
            continue
        now_mono = time.monotonic()
        elapsed = max(0.02, now_mono - last)
        last = now_mono
        now = time.time()
        if want_public:
            net.fetch_public_ip()

        payload: dict = {"seq": seq, "t": now, "elapsed": round(elapsed, 3), "interval": current_interval, "errors": []}
        slow_due = last_slow is None or now_mono - last_slow >= SLOW_SAMPLE_SECONDS
        if slow_due:
            try:
                sensors_cache = sensors.sample(now)
            except Exception as error:  
                sensors_cache = None
                payload["errors"].append(f"sensors: {error}")
            try:
                battery_cache = battery.sample()
            except Exception as error:  
                battery_cache = None
                payload["errors"].append(f"battery: {error}")
            if detail != DETAIL_NONE:
                since = elapsed if last_procs is None else max(0.05, now_mono - last_procs)
                try:
                    procs_cache = procs.sample(since, detail == DETAIL_ALL_PROCESSES, io_drives)
                except Exception as error:  
                    procs_cache = None
                    payload["errors"].append(f"procs: {error}")
                last_procs = now_mono
            else:
                procs.reset()
                procs_cache = None
                last_procs = None
            connections_cache = None
            network_primed = want_network
            if want_network:
                try:
                    connections_cache = procs.network_usage(detail == DETAIL_ALL_PROCESSES)
                except Exception as error:  
                    payload["errors"].append(f"connections: {error}")
            last_slow = now_mono
        for key, fn in (
            ("cpu", cpu.sample),
            ("power", lambda: power.sample(elapsed)),
            ("gpus", lambda: gpu.sample(slow_due, want_gpu)),
            ("mem", sample_memory),
            ("disks", lambda: disks.sample(elapsed, now)),
            ("net", lambda: net.sample(elapsed, now, detail != DETAIL_NONE)),
        ):
            try:
                payload[key] = fn()
            except Exception as error:  
                payload[key] = None
                payload["errors"].append(f"{key}: {error}")
        if slow_due:
            try:
                gpu_procs_cache = gpu.processes() if want_gpu else None
            except Exception as error:  
                gpu_procs_cache = None
                payload["errors"].append(f"gpu processes: {error}")
        cards = payload.get("gpus") or []
        if gpu_procs_cache is not None:
            for card in cards:
                card["procs"] = gpu_procs_cache.get(card["id"], [])
        payload["gpu"] = cards[0] if cards else None
        if isinstance(payload.get("net"), dict):
            payload["net"]["procs"] = connections_cache
        payload["sensors"] = sensors_cache
        payload["battery"] = battery_cache
        payload["procs"] = procs_cache
        try:
            sys.stdout.buffer.write(encode_payload(payload))
            sys.stdout.buffer.flush()
        except BrokenPipeError:
            break
        seq += 1
        if once:
            break
        controller.pause(max(0.02, current_interval - (time.monotonic() - now_mono)))

    gpu.stop()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
