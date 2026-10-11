#!/usr/bin/env python3
import argparse
import json

from binding_source import get_hyprctl_binds
from binding_metadata import annotate_bindings_with_display_metadata
from hint_formats import format_submap_hint, format_markdown_bindings, format_dmenu_bindings, format_rofi_bindings

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Hyprland keybinds hint script")
    parser.add_argument(
        "--format",
        choices=["json", "md", "dmenu", "rofi", "hint"],
        default="json",
        help="Output format",
    )
    parser.add_argument(
        "--submap",
        metavar="NAME",
        help="Only show binds belonging to this submap",
    )
    args = parser.parse_args()
    binds_data = get_hyprctl_binds()
    if binds_data:
        annotate_bindings_with_display_metadata(binds_data)
        if args.submap:
            binds_data = [b for b in binds_data if b.get("submap") == args.submap]
        if args.format == "json":
            print(json.dumps(binds_data, indent=4))
        elif args.format == "md":
            print(format_markdown_bindings(binds_data))
        elif args.format == "dmenu":
            print(format_dmenu_bindings(binds_data))
        elif args.format == "rofi":
            print(format_rofi_bindings(binds_data))
        elif args.format == "hint":
            print(format_submap_hint(binds_data))
