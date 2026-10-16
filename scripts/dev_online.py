#!/usr/bin/env python3
"""Run the local EO server and Android adapter, optionally routing a connected phone."""
import argparse
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def listening(port):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=0.3):
            return True
    except OSError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='ADB device serial; adds reverse tcp:8079')
    parser.add_argument('--adb', type=Path, help='Path to Android SDK adb')
    args = parser.parse_args()
    children = []
    logs = []
    logdir = ROOT / 'builds/logs'
    logdir.mkdir(parents=True, exist_ok=True)
    try:
        for name, port, command in [
            ('etheos', 8078, [sys.executable, str(ROOT / 'server/run.py')]),
            ('gateway', 8079, [sys.executable, str(ROOT / 'server/gateway.py')]),
        ]:
            if listening(port):
                print(f'Reusing service on 127.0.0.1:{port}', flush=True)
                continue
            stream = (logdir / f'{name}-dev.log').open('a')
            logs.append(stream)
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            children.append(process)
            deadline = time.monotonic() + 25
            while not listening(port):
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError(f'{name} did not start; see {logdir / (name + "-dev.log")}')
                time.sleep(0.2)
            print(f'Started {name} on 127.0.0.1:{port}', flush=True)
        if args.device:
            sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk')))
            adb = str(args.adb or (sdk / 'platform-tools/adb'))
            if not Path(adb).is_file():
                adb = shutil.which('adb')
            if not adb:
                raise RuntimeError('ADB not found; pass --adb /path/to/adb')
            subprocess.run([adb, '-s', args.device, 'reverse', 'tcp:8079', 'tcp:8079'], check=True)
            print('Phone routed. In Play online use 127.0.0.1, port 8079.', flush=True)
        print('Local online services ready. Ctrl+C stops services started by this command.', flush=True)
        while True:
            for child in children:
                if child.poll() is not None:
                    raise RuntimeError('A service stopped; inspect builds/logs/*-dev.log')
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
        for stream in logs:
            stream.close()


if __name__ == '__main__':
    main()
