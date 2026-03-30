#!/usr/bin/env python3
import argparse
import os
import sys
import signal

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from pyutils.xdg_base_dirs import xdg_runtime_dir, xdg_state_home
from waybar_apply import handle_layout_navigation
from waybar_selector import layout_selector, select_layout_and_style, style_selector
from waybar_assets import generate_includes
from waybar_runtime import (
    STATE_FILE,
    ensure_state_file,
    kill_waybar_and_watcher,
    list_layouts_json_text,
    logger,
    refresh_waybar_assets,
    restart_waybar,
    restart_waybar_direct,
    source_env_file,
    synchronize_layout_state,
    update_border_radius,
    update_config,
    update_global_css,
    update_icon_size,
    update_style,
    watch_waybar,
    get_waybar_pid,
)
from waybar_state import get_current_layout_from_config, resolve_style_path, set_state_value


def should_skip_layout_sync(argv):
    css_only_flags = {
        '--update-border-radius',
        '-b',
        '--update-global-css',
        '-g',
        '--style',
        '-s',
    }
    structural_flags = {
        '--update',
        '-u',
        '--update-icon-size',
        '-i',
        '--generate-includes',
        '-G',
        '--config',
        '-c',
        '--set',
        '--next',
        '-n',
        '--prev',
        '-p',
        '--select-layout',
        '-L',
        '--select-style',
        '-Y',
        '--select',
        '-S',
        '--watch',
        '-w',
        '--json',
        '-j',
    }
    if any(flag in argv for flag in structural_flags):
        return False
    return any(flag in argv for flag in css_only_flags)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description='Waybar configuration management')
    parser.add_argument('--set', type=str, help='Set a specific layout')
    parser.add_argument('-n', '--next', action='store_true', help='Switch to the next layout')
    parser.add_argument('-p', '--prev', action='store_true', help='Switch to the previous layout')
    parser.add_argument('-g', '--update-global-css', action='store_true', help='Update global.css file')
    parser.add_argument('-c', '--config', type=str, help='Path to the source config.jsonc file')
    parser.add_argument('-s', '--style', type=str, help='Path to the source style.css file')
    parser.add_argument('-w', '--watch', action='store_true', help='Watch and restart Waybar if it dies')
    parser.add_argument('--json', '-j', action='store_true', help='List all layouts in JSON format')
    parser.add_argument('--select-layout', '-L', action='store_true', help='Select a layout using rofi')
    parser.add_argument('--select-style', '-Y', action='store_true', help='Select a style using rofi')
    parser.add_argument('--select', '-S', action='store_true', help='Select layout and then style')
    parser.add_argument('-G', '--generate-includes', action='store_true', help='Generate includes.json file')
    parser.add_argument('--kill', '-k', action='store_true', help='Kill all Waybar instances and watcher script')
    parser.add_argument('--hide', action='store_true', help='Send SIGUSR1 to Waybar systemd unit to toggle hide')
    parser.add_argument('--restart-direct', action='store_true', help='Restart Waybar immediately without deferring to the watcher')
    parser.add_argument('-u', '--update', action='store_true', help='Update all (icon size, border radius, includes, config, style)')
    parser.add_argument('-i', '--update-icon-size', action='store_true', help='Update icon size in JSON files')
    parser.add_argument('-b', '--update-border-radius', action='store_true', help='Update border radius in CSS file')
    return parser.parse_args(argv)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    logger.debug('Starting waybar.py')

    if '--hide' in argv:
        pid = get_waybar_pid()
        if pid:
            try:
                os.kill(pid, signal.SIGUSR1)
                logger.info(f'Sent SIGUSR1 to waybar (PID {pid}) to toggle visibility')
            except ProcessLookupError:
                logger.error('Waybar process not found')
            except Exception as exc:
                logger.error(f'Failed to send SIGUSR1 to waybar: {exc}')
        else:
            logger.warning('Waybar not running, cannot toggle visibility')
        return 0

    if '--kill' in argv or '-k' in argv:
        kill_waybar_and_watcher()
        return 0

    skip_layout_sync = should_skip_layout_sync(argv)
    source_env_file(os.path.join(str(xdg_runtime_dir()), 'hypr', 'environment'))
    source_env_file(os.path.join(str(xdg_state_home()), 'hypr', 'staterc'))
    source_env_file(os.path.join(str(xdg_state_home()), 'hypr', 'env-overrides'))
    synchronize_layout_state(skip_layout_sync)

    if not STATE_FILE.exists() or STATE_FILE.stat().st_size == 0:
        logger.debug("State file doesn't exist or is empty, creating it")
        ensure_state_file()
    else:
        logger.debug(f'Using existing state file: {STATE_FILE}')

    args = parse_args(argv)

    if args.update:
        current_layout = get_current_layout_from_config()
        if current_layout:
            style_path = resolve_style_path(current_layout)
            update_config(current_layout)
            update_style(style_path)
            set_state_value('WAYBAR_STYLE_PATH', style_path)
        refresh_waybar_assets()
        logger.debug('Updating config and style...')
    if args.update_global_css:
        update_global_css()
    if args.update_icon_size:
        update_icon_size()
    if args.update_border_radius:
        update_border_radius()
    if args.generate_includes:
        generate_includes()
    if args.restart_direct:
        restart_waybar_direct()
    if args.config:
        update_config(args.config)
    if args.style:
        update_style(args.style)
    if args.next or args.prev or args.set:
        handle_layout_navigation(
            '--next' if args.next else '--prev' if args.prev else '--set',
            argv,
        )
    if args.json:
        print(list_layouts_json_text())
        return 0
    if args.select_layout:
        layout_selector()
        return 0
    if args.select_style:
        style_selector()
        return 0
    if args.select:
        select_layout_and_style()
        return 0
    if args.watch:
        watch_waybar()
        return 0

    specific_action_taken = (
        args.update
        or args.update_global_css
        or args.update_icon_size
        or args.update_border_radius
        or args.generate_includes
        or args.restart_direct
        or args.config
        or args.style
        or args.next
        or args.prev
        or args.set
        or args.json
        or args.select_layout
        or args.select_style
        or args.select
    )

    if not specific_action_taken:
        refresh_waybar_assets()
        update_style(args.style)
        restart_waybar()
        return 0

    if not any(vars(args).values()):
        # unreachable with argparse defaults, kept for parity
        return 0
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
