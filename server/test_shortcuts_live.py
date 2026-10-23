#!/usr/bin/env python3
"""Real Godot client processes with separate clean user directories and native EO login."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
from test_online import provision
from run import state_path
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--fixture', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.fixture:
        fixture = json.loads(args.fixture.read_text())
    else:
        session, fixture = provision()
        session.close()
        time.sleep(.7)
        assert fixture['username'].startswith('dev') and fixture['character_name'].startswith('dev')
        with sqlite3.connect(state_path() / 'runtime/database.sdb') as db:
            db.execute('UPDATE characters SET spells=?, inventory=? WHERE account=? AND name=?', ('1,0;5,0;', '1,500;331,3;375,4;', fixture['username'], fixture['character_name']))
    assert fixture['username'].startswith('dev') and fixture['character_name'].startswith('dev')
    results = []
    with tempfile.TemporaryDirectory(prefix='astervale-shortcut-live-') as temp:
        private = Path(temp) / 'fixture.json'
        private.write_text(json.dumps(fixture)); private.chmod(0o600)
        for mode in ('seed', 'restore'):
            data = Path(temp) / mode
            env = dict(os.environ, XDG_DATA_HOME=str(data), XDG_CONFIG_HOME=str(data), ASTER_VALE_SHORTCUT_FIXTURE=str(private), ASTER_VALE_SHORTCUT_MODE=mode, ASTER_VALE_TEST_HOST=args.host)
            result = subprocess.run([args.godot, '--headless', '--path', str(ROOT / 'client'), '--script', 'res://tests/shortcut_server_live.gd'], env=env, capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            (ROOT / 'work' / ('shortcuts-live-' + mode + '.log')).write_text(output)
            print(output)
            assert result.returncode == 0 and 'SHORTCUT SERVER LIVE PASS:' in output and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output
            results.append(mode)
            time.sleep(.8)
    report = dict(result='passed', modes=results, independent_clean_user_directories=True, native_login_and_enter=True, actual_item_and_skill_assignment_ui=True, all_four_restored_from_server=True, restore_did_not_overwrite_server=True, native_inventory_and_learned_spells_unchanged=True, dev_fixture_only=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
if __name__ == '__main__': main()
