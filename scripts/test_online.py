#!/usr/bin/env python3
"""Exercise the actual Godot scene against a running local gateway and etheos."""
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
    args = parser.parse_args()
    if not args.godot:
        parser.error('Pass --godot /path/to/Godot executable.')
    with tempfile.TemporaryDirectory(prefix='aster-vale-online-') as temporary:
        env = dict(os.environ, XDG_DATA_HOME=temporary, XDG_CONFIG_HOME=temporary,
                   ASTER_VALE_TEST_HOST=os.environ.get("ASTER_VALE_TEST_HOST", "127.0.0.1"))
        try:
            result = subprocess.run(
                [args.godot, '--headless', '--path', str(ROOT / 'client'),
                 '--script', 'res://tests/online_live.gd'],
                env=env, capture_output=True, text=True, timeout=150)
        except subprocess.TimeoutExpired as error:
            for chunk in (error.stdout, error.stderr):
                if chunk:
                    print(chunk.decode(errors='replace') if isinstance(chunk, bytes) else chunk, end='')
            raise SystemExit('Online scene test timed out; normal device/desktop saves were untouched.')
        output = result.stdout + result.stderr
        print(output, end='')
        if result.returncode or 'ONLINE LIVE PASS:' not in output or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
            raise SystemExit('Live online scene test failed.')


if __name__ == '__main__':
    main()
