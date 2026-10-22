#!/usr/bin/env python3
"""Exercise real native founding/recruiting/admin/chat without using player data."""
from pathlib import Path
import os,sys,subprocess,shutil,time,json,secrets,tempfile,re,signal,select
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'server'))
import argparse
parser=argparse.ArgumentParser(description='Verify the complete native guild lifecycle in an isolated temporary world')
parser.add_argument('--runtime',type=Path,default=root/'work/server-build/runtime')
parser.add_argument('--report',type=Path,default=root/'docs/guild-full-native-report.json')
args=parser.parse_args()
from eo_session import Session,EOError
from live_session import LiveSession
from guilds import guild_settings
report={};proc=None;sessions=[]
with tempfile.TemporaryDirectory(prefix='aster-full-guild-') as temporary:
 runtime=Path(temporary)/'runtime'
 shutil.copytree(args.runtime.resolve(),runtime,ignore=shutil.ignore_patterns('database.sdb*','world.bak*','etheos-v*'))
 os.environ['ASTER_VALE_RUNTIME']=str(runtime);guild_settings.cache_clear()
 p=runtime/'config.local.ini';s=p.read_text()
 for k,v in {'Port':'18178','StartMap':'108','StartX':'8','StartY':'4','PasswordSalt':secrets.token_hex(32),'StartItems':'1,60000','StartItemsMale':'1,60000','StartItemsFemale':'1,60000'}.items():s=re.sub('^'+k+r'\s*=.*$',k+' = '+v,s,flags=re.M)
 s+='\nGuildCreateMembers = 3\n';p.write_text(s)
 log=(root/'work/guild-full-native-private.log').open('w')
 def stop():
  if proc and proc.poll() is None:proc.send_signal(signal.SIGINT);proc.wait(timeout=25)
 def drain(seconds=.1):
  until=time.monotonic()+seconds
  while time.monotonic()<until:
   for session in sessions:
    if session.sock and select.select([session.sock],[],[],.001)[0]:session.pump()
 def until(test,seconds=5):
  deadline=time.monotonic()+seconds
  while not test() and time.monotonic()<deadline:drain(.02)
  assert test(),'Native asynchronous state did not arrive'
 name=lambda:'dev'+''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(8))
 try:
  proc=subprocess.Popen([str(runtime/'etheos')],cwd=runtime,stdout=log,stderr=subprocess.STDOUT,env={k:v for k,v in os.environ.items() if not k.startswith('ETHEOS_')});time.sleep(1)
  for _ in range(5):
   username,password=name(),secrets.token_urlsafe(18)
   session=LiveSession('127.0.0.1',18178);session.register(username,password);session.login(username,password);characters=session.create_character(name());session.enter(characters['characters'][0]['id']);sessions.append(session)
   bob=next(n for n in session.state['npcs'] if n['id']==46);session.guild_open(bob['index'])
  founder,supporter,recruiter,joiner,leaver=sessions
  founder.guild_begin('TST','test guild');assert founder.item_amount(1)==60000
  drain(.2);assert all(s.guild_invitation for s in sessions[1:]);leaver.guild_support(False)
  supporter.guild_support(True);recruiter.guild_support(True)
  until(lambda:founder.guild_creation['ready']);assert founder.item_amount(1)==60000
  founder.guild_found('A native guild');assert founder.item_amount(1)==10000
  drain(.2);assert all(s.stats.get('guild_tag')=='TST' for s in sessions[:3]);report['create_support_and_confirm']=True
  joiner.guild_join('TST',supporter.state['self']['name']);until(lambda:'cannot recruit' in joiner.guild_notice);assert not joiner.stats.get('guild')
  report['unauthorised_recruiter_rejected']=True
  founder.guild_rank(recruiter.state['self']['name'],2);recruiter.guild_refresh();assert recruiter.guild['membership']['rank']==2
  joiner.guild_join('TST',recruiter.state['self']['name']);until(lambda:bool(recruiter.guild_requests))
  try:recruiter.guild_recruit(joiner.player_id,True)
  except EOError as exc:assert 'bank' in str(exc)
  else:raise AssertionError('Recruitment ignored empty guild bank')
  founder.guild_deposit(5000);assert founder.item_amount(1)==5000
  recruiter.guild_recruit(joiner.player_id,True);until(lambda:joiner.stats.get('guild_tag')=='TST')
  joiner.guild_refresh();assert joiner.guild['membership']['rank']==9
  founder.guild_refresh();assert founder.guild['membership']['bank']==4000
  report['native_recruiter_accept_and_bank_charge']=True
  founder.guild_description('Updated native description');assert founder.guild['membership']['description']=='Updated native description'
  founder.guild_ranks('Leader,Recruiter,Officer,,,,,,Member');assert founder.guild['membership']['ranks'][2]=='Officer'
  founder.guild_rank(joiner.state['self']['name'],3);joiner.guild_refresh();assert joiner.guild['membership']['rank']==3
  try:joiner.guild_description('Forbidden')
  except EOError:pass
  else:raise AssertionError('Ordinary member changed description')
  report['description_rank_names_promotion_and_permissions']=True
  founder.guild_rank(joiner.state['self']['name'],9);founder.guild_kick(joiner.state['self']['name']);joiner.guild_refresh();assert not joiner.guild['membership']
  report['demotion_and_native_kick']=True
  founder.chat_send('guild','Guild test hello');drain(1.0)
  assert any(e.get('channel')=='guild' and e.get('message')=='Guild test hello' for e in supporter.events)
  assert not any(e.get('channel')=='guild' and e.get('message')=='Guild test hello' for e in leaver.events)
  report['private_native_guild_chat']=True
  supporter.guild_refresh();supporter.guild_leave();assert not supporter.guild['membership']
  founder.guild_leave(disband=True);assert not founder.guild['membership']
  recruiter.guild_refresh();assert not recruiter.guild['membership']
  report['native_leave_and_disband']=True
  report.update(result='passed',isolated_runtime=True,founding_members_for_test=3,hosted_requirement_unchanged=True,player_database_copied=False)
 finally:
  for session in sessions:session.close()
  stop();log.close()
args.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
