#!/usr/bin/env python3
import argparse

from mediaplayer_controller import run


def parse_arguments():
    parser = argparse.ArgumentParser(description='A media player status tool')
    parser.add_argument('--players', nargs='*', type=str)
    parser.add_argument('--player', type=str)
    return parser.parse_args()


if __name__ == '__main__':
    run(parse_arguments())
