#!/usr/bin/env python3
"""Boot etheos, validate real content loads/SQLite/EO Init, then shut down cleanly."""
import argparse, json, os, pathlib, re, shutil, signal, socket, sqlite3, subprocess, time
from handshake import handshake
from run import state_path, ROOT

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state-dir');a=p.parse_args()
    state=state_path(a.state_dir);runtime=state/'runtime'
    # Refuse to test an unrelated process already bound to the target port.
    with socket.socket() as check:
        try:check.bind(('127.0.0.1',8078))
        except OSError:p.error('Port 8078 is already in use. Stop the local server before smoke testing.')
    log=state/'smoke.log';report={}
    with log.open('w') as f:
        command=['python3',str(ROOT/'run.py'),'--state-dir',str(state)]
        if shutil.which('stdbuf'): command=['stdbuf','-oL','-eL']+command
        process=subprocess.Popen(command,stdout=f,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                if process.poll() is not None:raise RuntimeError(f'Server exited with {process.returncode}; inspect {log}')
                text=log.read_text(errors='replace')
                if 'Command Audit:' in text:break
                time.sleep(0.1)
            else:raise RuntimeError('Server did not finish startup in 30 seconds')
            report['handshake']=handshake()
            report['maps_loaded']=re.findall(r'(\d+/\d+) maps loaded',text)
            report['quests_loaded']=re.findall(r'(\d+/\d+) quests loaded',text)
            report['parser_errors']=list(dict.fromkeys(line for line in text.splitlines() if any(s in line for s in ['Could not load quest','Syntax Error:','Validation Error:'])))
            report['incompatible_quest_ids']=sorted(set(int(x) for x in re.findall(r'Could not load quest: .*?/(\d+)\.eqf',text)))
            report['pub_counts']={kind:int(count) for count,kind in re.findall(r'(\d+) (items|npc types|spells|classes) loaded',text)}
            chest_lines=[line for line in text.splitlines() if 'chest spawn on map' in line]
            report['chest_warnings']={'count':len(chest_lines),'map_ids':sorted(set(int(x) for x in re.findall(r'chest spawn on map (\d+)',text)))}
            content=json.loads((state/'content-report.json').read_text())
            report['disabled_quests']=[{'id':q['id'],'reason':q['disabled_reason']} for q in content['quests'] if not q.get('enabled',True)]
            report['repaired_quests']=[q['id'] for q in content['quests'] if q.get('patches')]
            report['content_validation_passed']=not report['parser_errors'] and not chest_lines and not report['disabled_quests']
            report['listener_addresses']=[]
            for line in pathlib.Path('/proc/net/tcp').read_text().splitlines()[1:]:
                fields=line.split()
                if fields[3]=='0A' and int(fields[1].split(':')[1],16)==8078:
                    address=socket.inet_ntoa(bytes.fromhex(fields[1].split(':')[0])[::-1])
                    report['listener_addresses'].append(address)
            if report['listener_addresses']!=['127.0.0.1']:raise RuntimeError('Expected loopback-only listening socket')
            with sqlite3.connect(runtime/'database.sdb') as db:
                report['sqlite_integrity']=db.execute('PRAGMA integrity_check').fetchone()[0]
                report['sqlite_tables']=[row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
            report['binding']='127.0.0.1:8078';report['public_listing']=False
        finally:
            process.send_signal(signal.SIGINT)
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:process.kill();process.wait()
            report['shutdown_exit_code']=process.returncode
    report['result']='server_smoke_passed_with_content_gaps' if not report.get('content_validation_passed') else 'server_smoke_passed'
    report['scope']='Server baseline only. Godot Android client remains offline and does not yet connect.'
    (state/'smoke-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if report.get('sqlite_integrity')!='ok' or not report.get('handshake',{}).get('challenge_verified'):raise SystemExit(1)
if __name__=='__main__':main()
