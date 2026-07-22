#!/usr/bin/env python3
import argparse

from mediaplayer_actions import ACTIONS, run_action, run_menu
from mediaplayer_controller import run


def parse_arguments():
    parser = argparse.ArgumentParser(description='A media player status tool')
    parser.add_argument('--players', nargs='*', type=str)
    parser.add_argument('--player', type=str)
    parser.add_argument('--action', choices=sorted(ACTIONS))
    parser.add_argument('--menu', action='store_true')
    parser.add_argument('--alt', '-A', action='store_true')
    return parser.parse_args()


if __name__ == '__main__':
    args = parse_arguments()
    if args.menu:
        raise SystemExit(run_menu(args.player or ""))
    if args.action:
        raise SystemExit(run_action(args.action, args.player or ""))
    run(args)
