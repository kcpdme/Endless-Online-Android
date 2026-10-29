"""Duplicate names across accounts and recovery in an isolated native world."""
import json,secrets,shutil,socket,subprocess,tempfile,time
from pathlib import Path
from eo_session import Session,CharacterCreationError
from test_online import dev_name
ROOT=Path(__file__).resolve().parents[1]

def main():
    checks=[]
    def check(value,why):
        if not value:raise AssertionError(why)
        checks.append(why)
    with tempfile.TemporaryDirectory(prefix='aster-character-rejection-') as tmp:
        runtime=Path(tmp)/'runtime';shutil.copytree(ROOT/'work/class-run-v15/runtime',runtime,ignore=shutil.ignore_patterns('database.sdb*','*.log'))
        cfg=runtime/'config.local.ini';cfg.write_text(cfg.read_text()+'\nPort = 18988\nIPReconnectLimit = 0\nMaxCharacters = 3\n')
        log=Path(tmp)/'native.log'
        with log.open('w') as stream:
            world=subprocess.Popen([str(runtime/'etheos')],cwd=runtime,stdout=stream,stderr=subprocess.STDOUT);sessions=[]
            try:
                for _ in range(100):
                    try:
                        with socket.create_connection(('127.0.0.1',18988),timeout=.1):break
                    except OSError:time.sleep(.1)
                time.sleep(.5)
                for _ in range(2):
                    s=Session(port=18988);sessions.append(s);username=dev_name();password=secrets.token_urlsafe(18);s.register(username,password);s.login(username,password)
                owner,other=sessions;name=dev_name();owner.create_character(name)
                for collision in (name,name.upper()):
                    try:other.create_character(collision)
                    except CharacterCreationError as error:check(error.code==1 and 'already taken' in str(error),'Native duplicate names across accounts and letter case return the clear name-taken message')
                    else:raise AssertionError('Native world accepted a duplicate character name')
                check(other.characters==[] and len(owner.characters)==1,'Rejected duplicate never overwrites or copies character ownership')
                try:other.create_character('bad')
                except CharacterCreationError as error:check(error.code==4 and '4–12 letters' in str(error),'Invalid native name returns the actual supported name rule')
                else:raise AssertionError('Native world accepted an invalid name')
                other.create_character(dev_name());check(len(other.characters)==1,'A fresh name succeeds on the same session after multiple rejections')
                owner.create_character(dev_name());owner.create_character(dev_name())
                try:owner.create_character(dev_name())
                except CharacterCreationError as error:check(error.code==2 and 'no free character slots' in str(error),'Account-slot exhaustion has its own message')
                else:raise AssertionError('Native world accepted a fourth character')
                check(len(owner.characters)==3,'Full-account rejection preserves all three owned characters')
                report=dict(result='passed',checks=len(checks),assertions=checks,isolated_database=True,production_database_opened=False)
                path=ROOT/'work/creation-message/native-report.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
            finally:
                for s in sessions:s.close()
                world.terminate();world.wait(timeout=15)
if __name__=='__main__':main()
