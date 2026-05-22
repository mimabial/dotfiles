#!/usr/bin/env python3
# Renderer: Kvantum themes.
# Stage 1: pack kvantum assets → ~/.config/Kvantum/pywal16/  (with colors.map sub in wallpaper mode)
# Stage 2: pack kvantum assets → ~/.config/Kvantum/<PackSafe>/ via install_kvantum_theme.py (state-role patching)

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PALETTE = Path(sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
               os.environ.get("HYPR_STATE_HOME",
                              os.path.expanduser("~/.local/state/hypr")) + "/active-palette.json")
KV_ROOT  = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "Kvantum"
THEMES_DIR = Path(os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr"))) / "themes"
INSTALLER = Path.home() / ".local/lib/hypr/theme/lib/install_kvantum_theme.py"
PYWAL_JSON = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "wal" / "colors.json"

def cache_hit(h):
    return subprocess.run(["render-cache", "hit?", "kvantum", h]).returncode == 0
def cache_store(h):
    subprocess.run(["render-cache", "store", "kvantum", h])

def safe_kvantum_name(pack):
    name = re.sub(r"[\s#/]+", "_", pack).strip("_")
    return name or "hypr-theme"

def main():
    if not PALETTE.is_file():
        sys.exit(f"render/kvantum: missing {PALETTE}")
    palette = json.loads(PALETTE.read_text())
    src = palette.get("source", "")
    mode = palette.get("mode", "wallpaper")
    if not src.startswith("theme:"):
        # Wallpaper mode without a pack name: kvantum stage 1 still works with last-known pack via env;
        # stage 2 needs a pack. Skip stage 2 if no pack.
        pack_name = os.environ.get("HYPR_THEME", "")
    else:
        pack_name = src.removeprefix("theme:")

    pack_dir = THEMES_DIR / pack_name if pack_name else None
    kv_dir = pack_dir / "kvantum" if pack_dir else None
    src_kvconfig = kv_dir / "kvconfig.theme" if kv_dir else None
    src_svg = kv_dir / "kvantum.theme" if kv_dir else None
    src_map = kv_dir / "colors.map" if kv_dir else None

    if not (src_kvconfig and src_kvconfig.is_file() and src_svg and src_svg.is_file()):
        # No kvantum assets in pack — nothing to do.
        return

    # Build input hash from palette + pack kvantum sources + installer + this script
    hasher = hashlib.sha256()
    hasher.update(PALETTE.read_bytes())
    for p in (src_kvconfig, src_svg, src_map, INSTALLER, Path(__file__)):
        if p and p.is_file(): hasher.update(p.read_bytes())
    hasher.update(mode.encode())
    h = hasher.hexdigest()[:16]

    pywal16_kvconfig = KV_ROOT / "pywal16" / "pywal16.kvconfig"
    pywal16_svg = KV_ROOT / "pywal16" / "pywal16.svg"
    pack_safe = safe_kvantum_name(pack_name)
    pack_dest_dir = KV_ROOT / pack_safe
    pack_dest_kvconfig = pack_dest_dir / f"{pack_safe}.kvconfig"
    pack_dest_svg = pack_dest_dir / f"{pack_safe}.svg"

    outputs_ready = all(p.exists() for p in
                        (pywal16_kvconfig, pywal16_svg, pack_dest_kvconfig, pack_dest_svg))
    if cache_hit(h) and outputs_ready:
        return

    # --- Stage 1: pywal16 generic theme ---
    pywal16_dir = KV_ROOT / "pywal16"
    pywal16_dir.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(dir=str(pywal16_dir), prefix=".staging-"))
    try:
        tmp_kvconfig = staging / "pywal16.kvconfig"
        tmp_svg = staging / "pywal16.svg"
        # Strip ';' comments (matches wal.kvantum.sh's sed -E)
        cleaned = re.sub(r"^([^#].*?)\s*;.*$", r"\1", src_kvconfig.read_text(), flags=re.M)
        tmp_kvconfig.write_text(cleaned)
        shutil.copyfile(src_svg, tmp_svg)

        # Wallpaper-mode: apply colors.map substitutions against pywal palette
        if mode != "theme" and src_map and src_map.is_file() and PYWAL_JSON.is_file():
            pywal = json.loads(PYWAL_JSON.read_text())
            palette_full = {**pywal["colors"], **pywal["special"]}
            subs = []
            for line in src_map.read_text().splitlines():
                line = line.strip()
                if "=" not in line: continue
                hex_part, _, var = line.partition("=")
                hex_part = hex_part.strip()
                var = var.strip()
                if not re.fullmatch(r"#[0-9a-fA-F]{6}", hex_part): continue
                if var not in palette_full: continue
                subs.append((hex_part, palette_full[var]))
            if subs:
                for f in (tmp_kvconfig, tmp_svg):
                    content = f.read_text()
                    for old, new in subs:
                        content = re.sub(re.escape(old), new, content, flags=re.I)
                    f.write_text(content)

        os.replace(tmp_kvconfig, pywal16_kvconfig)
        os.replace(tmp_svg, pywal16_svg)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    # --- Stage 2: pack-named theme with state-role patching (install_kvantum_theme.py) ---
    if INSTALLER.is_file():
        pack_dest_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src_svg, pack_dest_svg)
        shutil.copyfile(src_kvconfig, pack_dest_kvconfig)
        env = {
            **os.environ,
            "COLORS_MAP": str(src_map) if src_map and src_map.is_file() else "",
            "PYWAL_JSON": str(PYWAL_JSON),
            "SOURCE_KVCONFIG_PATH": str(src_kvconfig),
            "SELECTED_COLOR_MODE": "0" if mode == "theme" else "1",
            "SVG_PATH": str(pack_dest_svg),
            "KVCONFIG_PATH": str(pack_dest_kvconfig),
        }
        try:
            subprocess.run(["python3", str(INSTALLER)], env=env, check=True)
        except subprocess.CalledProcessError as e:
            print(f"render/kvantum: installer failed: {e}", file=sys.stderr)
            sys.exit(1)

    cache_store(h)

if __name__ == "__main__":
    main()
