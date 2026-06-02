#!/usr/bin/env python3
import subprocess
import sys


def main():
    if len(sys.argv) < 3:
        print('usage: with-timeout.py SECONDS COMMAND [ARG...]', file=sys.stderr)
        return 2
    try:
        seconds = float(sys.argv[1])
    except ValueError:
        print(f'invalid timeout seconds: {sys.argv[1]}', file=sys.stderr)
        return 2
    cmd = sys.argv[2:]
    try:
        proc = subprocess.run(cmd, timeout=seconds)
        return proc.returncode
    except subprocess.TimeoutExpired:
        print(f'[with-timeout] command timed out after {seconds:g}s: {cmd[0]}', file=sys.stderr)
        return 124


if __name__ == '__main__':
    raise SystemExit(main())
