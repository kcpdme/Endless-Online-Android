#!/usr/bin/env python3
"""Run the gameplay smoke in temporary user data, preserving real player saves."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot'))
    parser.add_argument('--world', action='store_true', help='Run map, stack quantities and wide-screen checks')
    args = parser.parse_args()
    if not args.godot:
        parser.error('Pass --godot /path/to/Godot executable, or put godot on PATH.')
    with tempfile.TemporaryDirectory(prefix='aster-vale-test-') as temporary:
        env = dict(os.environ, XDG_DATA_HOME=temporary, XDG_CONFIG_HOME=temporary)
        try:
            result = subprocess.run(
                [args.godot, '--headless', '--path', str(ROOT / 'client'),
                 '--script', 'res://tests/world_smoke.gd' if args.world else 'res://tests/gameplay_smoke.gd'],
                env=env, capture_output=True, text=True, timeout=90)
        except subprocess.TimeoutExpired as error:
            for chunk in (error.stdout, error.stderr):
                if chunk:
                    print(chunk.decode(errors='replace') if isinstance(chunk, bytes) else chunk, end='')
            raise SystemExit('Gameplay smoke timed out; real player saves were untouched.')
        output = result.stdout + result.stderr
        print(output, end='')
        # Godot assertions may report failure without a nonzero process exit.
        marker = 'WORLD SMOKE PASS:' if args.world else 'GAMEPLAY SMOKE PASS:'
        if (result.returncode or marker not in output
                or 'SCRIPT ERROR:' in output or 'ERROR:' in output):
            raise SystemExit('Gameplay smoke failed; real player saves were untouched.')


if __name__ == '__main__':
    main()
