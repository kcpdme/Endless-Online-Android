#!/usr/bin/env python3
"""Operator recovery for legacy hashes; preserves all character data.

Stop the native world before use. Enter a password privately at the prompt, or
generate one into a new mode-0600 file. Never accepts a password in argv.
"""
import argparse,datetime,getpass,json,os,pathlib,secrets,sqlite3,subprocess

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime',type=pathlib.Path,required=True)
    p.add_argument('--username',required=True)
    p.add_argument('--generate-file',type=pathlib.Path)
    a=p.parse_args();runtime=a.runtime.resolve();username=a.username.strip().lower()
    config=(runtime/'config.local.ini').read_text()
    salt=next(line.split('=',1)[1].strip() for line in config.splitlines() if line.startswith('PasswordSalt = '))
    database=runtime/'database.sdb'
    with sqlite3.connect(database) as db:
        if not db.execute('SELECT 1 FROM accounts WHERE username=?',(username,)).fetchone():raise SystemExit('Account does not exist; nothing changed.')
        if a.generate_file:
            # Refuse overwriting any existing file, including symlinks.
            fd=os.open(a.generate_file,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            password=secrets.token_urlsafe(15)
            with os.fdopen(fd,'w') as f:f.write(f'Account: {username}\nTemporary password: {password}\nServer: wss://eo.kcpd.top/ws\n')
        else:
            password=getpass.getpass('New password (8–25 characters): ')
            if password!=getpass.getpass('Confirm new password: '):raise SystemExit('Passwords differ; nothing changed.')
        if not password.isascii() or not password.isprintable() or not 8<=len(password)<=25:raise SystemExit('Password must be 8–25 printable ASCII characters.')
        hashed=subprocess.run([str(runtime/'native-auth'),'--hash'],input=salt+username+password+'\n',text=True,capture_output=True,check=True).stdout.strip()
        if not hashed.startswith('$2') or len(hashed)!=60:raise SystemExit('Hash generation failed; nothing changed.')
        before=db.execute('SELECT * FROM characters WHERE account=? ORDER BY name',(username,)).fetchall()
        backup=runtime/'private-backups';backup.mkdir(mode=0o700,exist_ok=True)
        target=backup/('before-password-reset-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')+'.sdb')
        fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.close(fd)
        with sqlite3.connect(target) as copy:db.backup(copy)
        db.execute('UPDATE accounts SET password=?,password_version=3 WHERE username=?',(hashed,username))
        after=db.execute('SELECT * FROM characters WHERE account=? ORDER BY name',(username,)).fetchall()
        assert before==after
        db.commit()
    print(json.dumps({'password_reset':True,'version':3,'character_rows_unchanged':True,'characters_preserved':len(before),'private_backup_created':True,'credentials_printed':False}))

if __name__=='__main__':main()
