#!/usr/bin/env python
import argparse
import ctypes
import hashlib
import json
import os
import select
import struct
import threading
import time
import sys
import urllib.parse
import urllib.request

# Add the parent hypr lib directory to path so we can import pyutils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import pyutils.logger as logger
import pyutils.wrapper.libnotify as notify
import tomllib
from pyutils.xdg_base_dirs import (
    xdg_config_home,
    xdg_state_home,
)

logger = logger.get_logger()
SCHEMA_REF = None
SCHEMA_STRICT = False


def _read_float(value, default):
    try:
        parsed = float(value)
        if parsed > 0:
            return parsed
    except Exception:
        pass
    return float(default)


def _read_int(value, default):
    try:
        parsed = int(value)
        if parsed >= 0:
            return parsed
    except Exception:
        pass
    return int(default)


class InotifyFileWatcher:
    """Inotify watcher for one target file via its parent directory."""

    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_DELETE = 0x00000200
    EVENT_MASK = (
        IN_CLOSE_WRITE
        | IN_MOVED_FROM
        | IN_MOVED_TO
        | IN_CREATE
        | IN_DELETE
    )
    HEADER_SIZE = struct.calcsize("iIII")

    def __init__(self, target_file, on_change):
        self.target_file = os.path.abspath(target_file)
        self.target_dir = os.path.dirname(self.target_file) or "."
        self.target_name = os.path.basename(self.target_file)
        self.on_change = on_change
        self.libc = None
        self.fd = None
        self.wd = None
        self.stop_event = threading.Event()
        self.thread = None

    def start(self):
        try:
            os.makedirs(self.target_dir, exist_ok=True)
        except Exception:
            pass

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

            self.wd = self.libc.inotify_add_watch(
                self.fd,
                self.target_dir.encode(),
                self.EVENT_MASK,
            )
            if self.wd < 0:
                try:
                    os.close(self.fd)
                except Exception:
                    pass
                self.fd = None
                return False
        except Exception:
            self.fd = None
            return False

        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        return True

    def _run(self):
        while not self.stop_event.is_set():
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

            index = 0
            while index + self.HEADER_SIZE <= len(data):
                wd, _mask, _cookie, name_len = struct.unpack_from("iIII", data, index)
                index += self.HEADER_SIZE
                raw_name = data[index : index + name_len]
                index += name_len

                if wd != self.wd or name_len <= 0:
                    continue
                name = raw_name.split(b"\0", 1)[0].decode("utf-8", errors="ignore")
                if name != self.target_name:
                    continue
                try:
                    self.on_change()
                except Exception:
                    pass

    def stop(self):
        self.stop_event.set()
        if self.fd is not None:
            if self.libc is not None and self.wd is not None and self.wd >= 0:
                try:
                    self.libc.inotify_rm_watch(self.fd, self.wd)
                except Exception:
                    pass
            try:
                os.close(self.fd)
            except Exception:
                pass
            self.fd = None
        if self.thread is not None:
            self.thread.join(timeout=1.0)
            self.thread = None


def load_toml_file(toml_file):
    try:
        with open(toml_file, "rb") as file:
            return tomllib.load(file)
    except FileNotFoundError as e:
        error_message = f"TOML file not found: {e}"
        logger.error("TOML file not found: %s", e)
        notify.send("Error", error_message)
        return None
    except tomllib.TOMLDecodeError as e:
        error_message = f"Error decoding TOML file: {e}"
        logger.error(f"Error decoding TOML file: {e}")
        notify.send("Error", error_message)
        return None
    except IOError as e:
        error_message = f"IO error: {e}"
        logger.error("IO error: %s", e)
        notify.send("Error", error_message)
        return None


def _schema_cache_path(schema_url):
    cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "hypr", "schema-cache")
    os.makedirs(cache_dir, exist_ok=True)
    digest = hashlib.sha256(schema_url.encode("utf-8")).hexdigest()
    return os.path.join(cache_dir, f"{digest}.json")


def _load_schema(schema_ref, base_dir):
    if schema_ref is None:
        return None

    schema_ref = os.path.expandvars(os.path.expanduser(schema_ref))
    parsed = urllib.parse.urlparse(schema_ref)
    is_url = parsed.scheme in ("http", "https")

    if is_url:
        cache_path = _schema_cache_path(schema_ref)
        if os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        try:
            with urllib.request.urlopen(schema_ref, timeout=2) as resp:
                data = resp.read().decode("utf-8")
            schema = json.loads(data)
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump(schema, f)
            return schema
        except Exception as e:
            logger.warning("Failed to load schema URL: %s", e)
            notify.send("Schema", f"Failed to load schema URL: {e}")
            return None

    if not os.path.isabs(schema_ref):
        schema_ref = os.path.join(base_dir, schema_ref)
    if not os.path.exists(schema_ref):
        logger.warning("Schema file not found: %s", schema_ref)
        notify.send("Schema", f"Schema file not found: {schema_ref}")
        return None
    try:
        with open(schema_ref, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.warning("Failed to read schema file: %s", e)
        notify.send("Schema", f"Failed to read schema file: {e}")
        return None


def validate_schema(toml_content, toml_file):
    schema_ref = SCHEMA_REF
    if schema_ref is None and isinstance(toml_content, dict):
        schema_ref = toml_content.get("$schema") or toml_content.get("$SCHEMA")
    if schema_ref is None:
        schema_ref = os.environ.get("HYPR_CONFIG_SCHEMA")
    if schema_ref is None:
        return True

    try:
        import jsonschema
    except ImportError:
        msg = "jsonschema not installed; skipping schema validation."
        logger.warning(msg)
        notify.send("Schema", msg)
        return not SCHEMA_STRICT

    schema = _load_schema(schema_ref, os.path.dirname(toml_file))
    if schema is None:
        msg = "Schema not available; skipping validation."
        logger.warning(msg)
        notify.send("Schema", msg)
        return not SCHEMA_STRICT

    try:
        jsonschema.validate(instance=toml_content, schema=schema)
        return True
    except jsonschema.ValidationError as e:
        msg = f"Config schema validation failed: {e.message}"
        logger.error(msg)
        notify.send("Schema", msg)
        return False
    except jsonschema.SchemaError as e:
        msg = f"Schema error: {e.message}"
        logger.error(msg)
        notify.send("Schema", msg)
        return not SCHEMA_STRICT


def parse_toml_to_env(toml_file, env_file=None, export=False):
    ignored_keys = [
        "$schema",
        "$SCHEMA",
        "hyprland",
        "hyprland-ipc",
        "hyprland-start",
        "hyprland-env",
    ]

    toml_content = load_toml_file(toml_file)
    if toml_content is None:
        return
    if not validate_schema(toml_content, toml_file):
        return

    def flatten_dict(d, parent_key=""):
        logger.debug(f"Parent key: {parent_key}")
        items = []
        for k, v in d.items():
            # Skip if current key or parent key is in ignored keys
            if k in ignored_keys or parent_key.startswith("hyprland"):
                logger.debug(f"Skipping ignored key: {k}")
                continue

            if k.startswith("$"):
                continue
            new_key = f"{parent_key}_{k.upper()}" if parent_key else k.upper()
            if isinstance(v, dict):
                items.extend(flatten_dict(v, new_key).items())
            elif isinstance(v, list):
                array_items = " ".join(f'"{item}"' for item in v)
                items.append((new_key, f"({array_items})"))
            elif isinstance(v, bool):
                items.append((new_key, str(v).lower()))
            elif isinstance(v, int):
                items.append((new_key, v))
            else:
                items.append((new_key, f'"{v}"'))
        return dict(items)

    flat_toml_content = flatten_dict(toml_content)
    output = [
        f"export {key}={value}" if export else f"{key}={value}"
        for key, value in flat_toml_content.items()
    ]

    if env_file:
        with open(env_file, "w", encoding="UTF-8") as file:  # Use UTF-8 encoding
            file.write("\n".join(output) + "\n")
        logger.debug(
            f"Environment variables have been written to {env_file}"
        )  # Use % lazy formatting for better performance in logger

    else:
        logger.debug("\n".join(output))


def parse_toml_to_hypr(toml_file, hypr_file=None):
    logger.debug("Parsing Hyprland variables...")
    toml_content = load_toml_file(toml_file)
    if toml_content is None:
        return
    if not validate_schema(toml_content, toml_file):
        return

    def flatten_hypr_dict(d, parent_key=""):
        logger.debug(f"Parent key: {parent_key}")
        items = []
        for k, v in d.items():
            logger.debug(f"Current key=val: {k}={v}")
            # Track if we're inside a hyprland section
            is_hyprland_section = k.startswith("hyprland") or parent_key.startswith(
                "hyprland"
            )

            if is_hyprland_section:
                logger.debug(f"Found hyprland key: {k}")
                # Remove 'hyprland_' prefix if it exists
                new_key = k.replace("hyprland_", "") if k.startswith("hyprland_") else k
                # If parent_key exists, combine it with current key
                if parent_key and not parent_key.startswith("hyprland"):
                    new_key = f"{parent_key}_{new_key}"
                elif parent_key.startswith("hyprland"):
                    new_key = (
                        f"${parent_key[9:]}.{new_key.upper()}"
                        if parent_key[9:]
                        else f"${new_key.upper()}"
                    )

                if isinstance(v, dict):
                    items.extend(flatten_hypr_dict(v, new_key).items())
                elif isinstance(v, list):
                    array_items = ", ".join(str(item) for item in v)
                    items.append((new_key, array_items))
                elif isinstance(v, bool):
                    items.append((new_key, str(v).lower()))
                elif isinstance(v, (int, float)):
                    items.append((new_key, str(v)))
                else:
                    items.append((new_key, str(v)))

            else:
                logger.debug(f"Skipping key: {k}")
        return dict(items)

    flat_toml_content = flatten_hypr_dict(toml_content)
    logger.debug(f"Toml Content {toml_content}")
    output = [f"{key}={value}" for key, value in flat_toml_content.items()]

    if not hypr_file:
        hypr_file = HYPR_FILE

    if hypr_file:
        with open(hypr_file, "w", encoding="UTF-8") as file:
            file.write("\n".join(output) + "\n")
        logger.debug(f"Hyprland variables have been written to {hypr_file}")
    else:
        logger.debug("No hypr file specified.")
        logger.debug("\n".join(output))


def _get_mtime_ns(path):
    try:
        return os.stat(path).st_mtime_ns
    except FileNotFoundError:
        return None
    except Exception:
        return None


def watch_file(
    toml_file,
    env_file=None,
    export=False,
    hypr_file=None,
    watchdog_seconds=60.0,
    debounce_ms=150,
    stop_event=None,
):
    if stop_event is None:
        stop_event = threading.Event()

    watchdog_seconds = _read_float(watchdog_seconds, 60.0)
    debounce_seconds = _read_float(debounce_ms, 150.0) / 1000.0

    change_event = threading.Event()

    watcher = InotifyFileWatcher(toml_file, change_event.set)
    using_inotify = watcher.start()
    if using_inotify:
        logger.debug("Using inotify watcher for %s", toml_file)
    else:
        logger.warning("inotify unavailable, using watchdog-only mtime checks for %s", toml_file)

    last_mtime = _get_mtime_ns(toml_file)
    logger.debug(
        "Watching %s (watchdog=%ss, debounce=%sms)",
        toml_file,
        watchdog_seconds,
        int(debounce_seconds * 1000),
    )

    try:
        while not stop_event.is_set():
            woke_by_event = change_event.wait(timeout=watchdog_seconds)
            if stop_event.is_set():
                break

            if woke_by_event:
                change_event.clear()
                while not stop_event.is_set() and change_event.wait(timeout=debounce_seconds):
                    change_event.clear()
                if stop_event.is_set():
                    break

            current_mtime = _get_mtime_ns(toml_file)
            changed = current_mtime != last_mtime
            should_parse = changed or woke_by_event
            if not should_parse:
                continue

            last_mtime = current_mtime
            logger.debug(
                "Config refresh trigger (%s) for %s",
                "event" if woke_by_event else "watchdog",
                toml_file,
            )
            parse_toml_to_env(toml_file, env_file, export)
            parse_toml_to_hypr(toml_file, hypr_file)
    finally:
        watcher.stop()


def parse_args():
    default_watchdog = _read_float(
        os.environ.get("HYPR_CONFIG_WATCHDOG_SECONDS", "60"),
        60.0,
    )
    default_debounce_ms = _read_int(
        os.environ.get("HYPR_CONFIG_DEBOUNCE_MS", "150"),
        150,
    )

    parser = argparse.ArgumentParser(
        description="Parse a TOML file and optionally watch for changes."
    )
    parser.add_argument(
        "--input",
        default=os.path.join(
            xdg_config_home(),
            "hypr/config.toml",
        ),
        help="The input TOML file to parse. Default is $XDG_CONFIG_HOME/hypr/config.toml",
    )
    parser.add_argument(
        "--env",
        default=os.path.join(
            xdg_state_home(),
            "hypr/config",
        ),
        help="The output environment file. Default is $XDG_STATE_HOME/hypr/config",
    )
    parser.add_argument(
        "--hypr",
        default=os.path.join(
            xdg_state_home(),
            "hypr/hyprland.conf",
        ),
        help="The output Hyprland file. Default is $XDG_STATE_HOME/hyprland.conf",
    )
    parser.add_argument(
        "--schema",
        help="JSON schema path/URL to validate the TOML file (overrides $schema).",
    )
    parser.add_argument(
        "--schema-strict",
        action="store_true",
        help="Fail when schema validation fails or schema is unavailable.",
    )
    parser.add_argument(
        "--daemon", action="store_true", help="Run in daemon mode to watch for changes."
    )
    parser.add_argument(
        "--watchdog-seconds",
        type=float,
        default=default_watchdog,
        help="Fallback mtime watchdog interval in seconds (default: %(default)s).",
    )
    parser.add_argument(
        "--debounce-ms",
        type=int,
        default=default_debounce_ms,
        help="Debounce window for bursty file saves in milliseconds (default: %(default)s).",
    )
    parser.add_argument("--export", action="store_true", help="Export the parsed data.")
    return parser.parse_args()


def main():
    args = parse_args()

    global CONFIG_FILE, ENV_FILE, HYPR_FILE, SCHEMA_REF, SCHEMA_STRICT
    CONFIG_FILE = args.input
    ENV_FILE = args.env
    HYPR_FILE = args.hypr
    SCHEMA_REF = args.schema
    SCHEMA_STRICT = args.schema_strict

    daemon_mode = args.daemon
    export_mode = args.export
    watchdog_seconds = args.watchdog_seconds
    debounce_ms = args.debounce_ms

    if daemon_mode:
        # Generate the config on launch
        parse_toml_to_hypr(CONFIG_FILE, HYPR_FILE)
        parse_toml_to_env(CONFIG_FILE, ENV_FILE, export_mode)

        try:
            watch_file(
                CONFIG_FILE,
                ENV_FILE,
                export_mode,
                HYPR_FILE,
                watchdog_seconds,
                debounce_ms,
            )
        except KeyboardInterrupt:
            logger.info("Daemon mode stopped.")
    else:
        parse_toml_to_env(CONFIG_FILE, ENV_FILE, export_mode)
        parse_toml_to_hypr(CONFIG_FILE, HYPR_FILE)


if __name__ == "__main__":
    main()
