#!/usr/bin/env python3
"""Exercise the production Keystore vault in a separate disposable Android test UID."""
from pathlib import Path
import argparse,json,subprocess,zipfile,shutil
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--device',required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
 sdk=Path.home()/'Android/Sdk';bt=sdk/'build-tools/37.0.0';android=sdk/'platforms/android-36/android.jar';out=ROOT/'work/vault-test';out.mkdir(exist_ok=True)
 def run(cmd):return subprocess.check_output(list(map(str,cmd)),stderr=subprocess.STDOUT,text=True)
 manifest=out/'AndroidManifest.xml';manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.cloudgameboy.astervale.vaulttest"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/><application android:debuggable="true" android:allowBackup="false" android:label="Aster Vault Test"/><instrumentation android:name="com.cloudgameboy.astervale.vaulttest.VaultInstrumentation" android:targetPackage="com.cloudgameboy.astervale.vaulttest"/></manifest>')
 classes=out/'classes';shutil.rmtree(classes,ignore_errors=True);classes.mkdir()
 run(['javac','--release','8','-classpath',android,'-d',classes,ROOT/'platform/android/com/cloudgameboy/astervale/CredentialVault.java',ROOT/'platform/android/tests/VaultInstrumentation.java'])
 dex=out/'dex';dex.mkdir(exist_ok=True);run([bt/'d8','--min-api','26','--lib',android,'--output',dex,*classes.rglob('*.class')])
 unsigned=out/'unsigned.apk';run([bt/'aapt2','link','-o',unsigned,'--manifest',manifest,'-I',android])
 with zipfile.ZipFile(unsigned,'a') as z:z.write(dex/'classes.dex','classes.dex')
 apk=out/'test.apk';run([bt/'zipalign','-f','4',unsigned,apk]);run([bt/'apksigner','sign','--ks',ROOT/'work/toolchain/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','pass:android',apk])
 adb=[sdk/'platform-tools/adb','-s',a.device]
 try:
  run(adb+['install','--no-incremental','-r',apk])
  for phase in ('first','second'):
   run(adb+['shell','am','force-stop','com.cloudgameboy.astervale.vaulttest'])
   output=run(adb+['shell','am','instrument','-w','-e','phase',phase,'com.cloudgameboy.astervale.vaulttest/com.cloudgameboy.astervale.vaulttest.VaultInstrumentation'])
   assert 'result=passed' in output,output
  a.report.write_text(json.dumps(dict(result='passed',android_keystore_aes_gcm=True,ciphertext_not_plaintext=True,random_iv=True,across_process_restore=True,tamper_rejected=True,forget_deletes_key_and_file=True,separate_test_uid=True),indent=2)+'\n');print('ANDROID KEYSTORE VAULT: passed')
 finally:run(adb+['uninstall','com.cloudgameboy.astervale.vaulttest'])
if __name__=='__main__':main()
