#!/usr/bin/env python3
"""Run the real Godot social/storage dialogs against a disposable native world.

Uses fresh dev accounts and ports 18878-18880. Never reads or edits a live DB.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time


def main():
    from run import state_path
    from eo_session import Session
    import test_online
    root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', type=Path, required=True)
    p.add_argument('--state-dir', required=True)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    state = state_path(a.state_dir)
    with tempfile.TemporaryDirectory(prefix='aster-social-isolated-') as temp:
        base = Path(temp)
        runtime = base / 'runtime'
        shutil.copytree(state / 'runtime', runtime, ignore=shutil.ignore_patterns('database.sdb*', '*.log', 'world.bak*', 'etheos-v*'))
        shutil.copy2(state / 'build/etheos', runtime / 'etheos')
        config = runtime / 'config.local.ini'
        config.write_text(re.sub(r'^Port\s*=.*$', 'Port = 18878', config.read_text(), flags=re.M))
        children = []
        logs = []
        def start(name, command, port, cwd=None):
            log = (base / (name + '.log')).open('w'); logs.append(log)
            env = dict(os.environ, ASTER_VALE_RUNTIME=str(runtime), ASTER_VALE_SHORTCUT_DB=str(base / 'shortcuts.sqlite3'))
            child = subprocess.Popen([str(v) for v in command], cwd=cwd or root, env=env, stdout=log, stderr=subprocess.STDOUT)
            children.append(child)
            for _ in range(100):
                if child.poll() is not None: raise RuntimeError(name + ' failed to start')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                except OSError: time.sleep(.1)
            else: raise TimeoutError(name)
            time.sleep(.6)
        try:
            start('native', [runtime / 'etheos'], 18878, runtime)
            test_online.Session = lambda: Session(port=18878)
            fixtures = {}
            for role in ('actor', 'observer'):
                session, fixture = test_online.provision()
                session.close(); fixtures[role] = fixture
            time.sleep(1)
            with sqlite3.connect(runtime / 'database.sdb') as db:
                for role, y in [('actor', 3), ('observer', 2)]:
                    f = fixtures[role]
                    assert f['username'].startswith('dev') and f['character_name'].startswith('dev')
                    db.execute('UPDATE characters SET map=90,x=2,y=?,level=50,hp=500,tp=1,int=40,wis=40,con=40,inventory=?,goldbank=0,bank="",bankmax=0 WHERE account=? AND name=?', (y, '1,50000;21,5;281,2;', f['username'], f['character_name']))
            start('gateway', [sys.executable, root / 'server/gateway.py', '--port', '18879', '--eo-port', '18878'], 18879)
            start('websocket', [sys.executable, root / 'server/ws_gateway.py', '--port', '18880', '--tcp-port', '18879', '--deps-dir', state / 'python'], 18880)
            private = base / 'fixtures.json'
            private.write_text(json.dumps(fixtures)); private.chmod(0o600)
            env = dict(os.environ, XDG_DATA_HOME=str(base / 'data'), XDG_CONFIG_HOME=str(base / 'config'), ASTER_VALE_PEER_FIXTURES=str(private), ASTER_VALE_TEST_HOST='ws://127.0.0.1:18880/ws', ASTER_VALE_TEST_REPORT=str(a.report.resolve()))
            result = subprocess.run([str(a.godot.resolve()), '--headless', '--path', str(root / 'client'), '--audio-driver', 'Dummy', '--script', 'res://tests/services_live.gd'], env=env, capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            assert result.returncode == 0 and 'SERVICES UI LIVE PASS:' in output and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output, output[-5000:]
            print(a.report.read_text())
        finally:
            for child in reversed(children):
                if child.poll() is None:
                    child.send_signal(signal.SIGINT)
                    try: child.wait(timeout=25)
                    except subprocess.TimeoutExpired: child.kill(); child.wait()
            for log in logs: log.close()


if __name__ == '__main__': main()
