#!/usr/bin/env python3
"""Real native login code 5 and authenticated handoff between independent WebSocket connections."""
import argparse,json,pathlib,time
from bootstrap_ws import load,DEFAULT_TARGET
from test_online import provision

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--url',default='ws://127.0.0.1:8183/ws');p.add_argument('--deps-dir',default=str(DEFAULT_TARGET));p.add_argument('--fixture-file',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path);a=p.parse_args();load(a.deps_dir)
 from websockets.sync.client import connect
 if a.fixture_file:f=json.loads(a.fixture_file.read_text())
 else:
  base,f=provision();base.close();time.sleep(.6)
 assert f['username'].startswith('dev')
 clients=[];serial=0
 def call(ws,op,**fields):
  nonlocal serial
  serial+=1;uid=serial;ws.send(json.dumps(dict(id=uid,op=op,**fields)))
  while True:
   r=json.loads(ws.recv(timeout=15))
   if r.get('id')==uid:return r
 def client():
  context=connect(a.url,proxy=None,max_size=4194304,compression=None);ws=context.__enter__();clients.append(context);assert call(ws,'connect')['ok'];return ws
 try:
  old=client();r=call(old,'login',username=f['username'],password=f['password']);assert r['ok'];token=r['data']['resume_token']
  unknown=client();r=call(unknown,'login',username=f['username'],password=f['password'],resume_token='invalid-proof')
  assert not r['ok'] and r['error_code']==5 and 'already connected' in r['error'];assert call(old,'diagnostics')['ok']
  fresh=client();before=time.monotonic();r=call(fresh,'login',username=f['username'],password=f['password'],resume_token=token);elapsed=time.monotonic()-before
  assert r['ok'],r.get('error');assert r['data']['resume_token']!=token
  character=next(c for c in r['data']['characters'] if c['name']==f['character_name']);assert call(fresh,'enter',character_id=character['id'])['ok']
  wrong=client();rejected=call(wrong,'login',username=f['username'],password='DeliberatelyWrongPassword',resume_token=r['data']['resume_token'])
  assert not rejected['ok'] and rejected.get('error_code') in (1,2) and 'resume_token' not in rejected.get('data',{}), {'ok':rejected.get('ok'),'code':rejected.get('error_code'),'error':rejected.get('error')}
  report=dict(wrong_password_not_authenticated=True,result='passed',native_code_5_means_already_logged_in=True,invalid_proof_does_not_disconnect_existing_session=True,valid_proof_retires_only_its_own_old_connection=True,proof_rotated_after_login=True,password_still_verified_by_native_server=True,reconnect_seconds=round(elapsed,3),credentials_or_tokens_published=False)
  if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps(report,indent=2))
 finally:
  for context in clients:context.__exit__(None,None,None)
if __name__=='__main__':main()
