#!/usr/bin/env python3
"""Reproduce completed, active and new Piglet Trouble with a disposable native DB."""
import argparse
import json
import os
from pathlib import Path
import secrets
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
from eo_session import EOError, Session
from live_session import LiveSession
from test_online import dev_name


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();checks=0
    def check(ok,why):
        nonlocal checks
        assert ok,why
        checks+=1
    with tempfile.TemporaryDirectory(prefix='aster-newbie-quests-') as temp:
        root=Path(temp);r=root/'runtime'
        shutil.copytree(a.runtime,r,ignore=shutil.ignore_patterns('database.sdb*','*.log','etheos-v*'))
        shutil.copy2(a.binary,r/'etheos');os.environ['ASTER_VALE_RUNTIME']=str(r)
        cfg=r/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18975\nIPReconnectLimit = 0\n')
        log=(root/'native.log').open('w');proc=subprocess.Popen([str(r/'etheos')],cwd=r,stdout=log,stderr=subprocess.STDOUT)
        clients=[]
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',18975),timeout=.1):break
                except OSError:time.sleep(.1)
            time.sleep(.8)
            fixtures=[]
            states={
                'completed':'0,island,{};28,end,{};29,end,{};49,begin,{killednpcs/6=1};',
                'active':'0,island,{};28,begin,{killednpcs/230=7};49,begin,{killednpcs/6=1};',
                'new':'0,island,{};29,end,{};49,begin,{killednpcs/6=1};',
            }
            for kind in states:
                f=dict(kind=kind,username=dev_name(),password=secrets.token_urlsafe(18),name=dev_name())
                s=Session(port=18975)
                try:
                    s.register(f['username'],f['password']);s.login(f['username'],f['password']);s.create_character(f['name'])
                finally:s.close()
                fixtures.append(f)
            time.sleep(.8)
            with sqlite3.connect(r/'database.sdb') as db:
                for f in fixtures:
                    check(f['username'].startswith('dev') and f['name'].startswith('dev'),'Only private dev characters are staged')
                    db.execute('UPDATE characters SET map=190,x=20,y=22,level=2,exp=1365,hp=500,quest=? WHERE account=? AND name=?',(states[f['kind']],f['username'],f['name']))
            for f in fixtures:
                s=LiveSession('127.0.0.1',18975);clients.append(s)
                chars=s.login(f['username'],f['password'])['characters'];s.enter(next(c['id'] for c in chars if c['name']==f['name']))
                s.snapshot();before=s.stats['experience'];inventory=list(s.inventory)
                npc=next(n for n in s.state['npcs'] if n['id']==154)
                s.quest_list('progress');previous=s.quest_journal
                snake=next(q for q in previous['entries'] if q['name']=='Snake Hunt (rep)')
                check((snake['progress'],snake['target'])==(1,3),'Existing snake progress is native and preserved')
                if f['kind']=='completed':
                    for _ in range(2):
                        try:s.quest_open(npc['index'])
                        except EOError as exc:check('already completed Piglet Trouble' in str(exc),'Completed one-time quest reports completion')
                        else:raise AssertionError('Completed Piglet Trouble must not reopen')
                    check(s.quest_journal is previous,'Completion lookup preserves the open quest-book page')
                    check(s.stats['experience']==before and s.inventory==inventory,'Reopening cannot grant duplicate rewards')
                    s.quest_list('history')
                    check({'Piglet Trouble','Goat Business'} <= {q['name'] for q in s.quest_journal['entries']},'Both finished original quests remain in native history')
                else:
                    data=s.quest_open(npc['index'])['quest_dialog']
                    check(data['quest_id']==28 and any('piglets' in page for page in data['pages']),'Original piglet dialogue opens alongside Snake Hunt')
                    s.quest_reply(2);s.quest_list('progress')
                    piglet=next(q for q in s.quest_journal['entries'] if q['name']=='Piglet Trouble')
                    check(piglet['description']=='Kill 10 normal piglets.','Original piglet objective is unchanged')
                s.close();clients.remove(s)
                time.sleep(.8)
                with sqlite3.connect(r/'database.sdb') as db:
                    saved=db.execute('SELECT quest FROM characters WHERE account=? AND name=?',(f['username'],f['name'])).fetchone()[0]
                if f['kind']=='active':
                    check(bool(re.search(r'28,begin,\{[^}]*killednpcs/230=7',saved)),'Seven piglet kills persist after reopening and replying')
                elif f['kind']=='completed':
                    check('28,end,{};' in saved,'Completed piglet quest is never reset')
                else:check('28,begin,' in saved,'New piglet quest persists alongside the active snake quest')
            report=dict(result='passed',checks=checks,isolated_database=True,original_quests_unchanged=True,
                        completed_piglet_is_one_time=True,unrelated_snake_quest_does_not_block_piglet=True,
                        active_piglet_progress=[7,10],duplicate_rewards=False,open_journal_preserved=True)
            a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
        finally:
            for s in clients:s.close()
            if proc.poll() is None:
                proc.send_signal(signal.SIGINT)
                try:proc.wait(timeout=25)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            log.close()


if __name__=='__main__':main()
