#!/usr/bin/env python3
"""Reproducible Android debug, Linux or browser preview export. Never publishes."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import re
from bootstrap_godot import bootstrap

ROOT = Path(__file__).resolve().parents[1]

def run_checked(command, env, name):
    """Godot can return zero for script errors, so inspect diagnostics as well."""
    logdir = ROOT / 'builds' / 'logs'
    logdir.mkdir(parents=True, exist_ok=True)
    log = logdir / (name + '.log')
    with log.open('w') as stream:
        result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text(errors='replace')
    diagnostics = [line for line in output.splitlines() if re.search(r'(^|\s)(SCRIPT ERROR:|ERROR:)', line)]
    if result.returncode or diagnostics:
        print('\n'.join(output.splitlines()[-35:]))
        raise RuntimeError(f'{name} failed (exit {result.returncode}); see {log}')
    print(f'{name}: passed; log {log}')

def quoted(value):
    return json.dumps(str(value))

def configure(toolchain, cache, sdk):
    templates = Path(toolchain['templates'])
    config = cache / 'config'
    data = cache / 'data'
    (config / 'godot').mkdir(parents=True, exist_ok=True)
    data.mkdir(parents=True, exist_ok=True)
    java = Path(os.environ.get('JAVA_HOME', '/usr/lib/jvm/java-17-openjdk-amd64'))
    key = cache / 'debug.keystore'
    if not key.exists():
        subprocess.run([str(java / 'bin/keytool'), '-genkeypair', '-noprompt', '-keystore', str(key),
                        '-storepass', 'android', '-alias', 'androiddebugkey', '-keypass', 'android',
                        '-dname', 'CN=Aster Vale Debug,O=Development,C=IN', '-keyalg', 'RSA',
                        '-keysize', '2048', '-validity', '10000'], check=True, capture_output=True)
    settings = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    settings += f'export/android/android_sdk_path = {quoted(sdk)}\n'
    settings += f'export/android/java_sdk_path = {quoted(java)}\n'
    settings += f'export/android/debug_keystore = {quoted(key)}\n'
    settings += 'export/android/debug_keystore_user = "androiddebugkey"\n'
    settings += 'export/android/debug_keystore_pass = "android"\n'
    settings += 'export/android/shutdown_adb_on_exit = false\n'
    (config / 'godot/editor_settings-4.7.tres').write_text(settings)
    presets = f'''[preset.0]
name="Android"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
export_path="../builds/aster-vale-debug.apk"

[preset.0.options]
custom_template/debug={quoted(templates / 'android_debug.apk')}
custom_template/release={quoted(templates / 'android_release.apk')}
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=true
version/code=4
version/name="0.4.0"
package/unique_name="io.astervale.prototype"
package/name="Aster Vale"
package/signed=true
screen/immersive_mode=true
permissions/internet=true

[preset.1]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
export_path="../builds/web/index.html"

[preset.1.options]
custom_template/debug={quoted(templates / 'web_nothreads_debug.zip')}
custom_template/release={quoted(templates / 'web_nothreads_release.zip')}
variant/extensions_support=false
variant/thread_support=false
html/export_icon=true
progressive_web_app/enabled=false

[preset.2]
name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
export_path="../builds/linux/aster-vale.x86_64"

[preset.2.options]
custom_template/debug={quoted(templates / 'linux_debug.x86_64')}
custom_template/release={quoted(templates / 'linux_release.x86_64')}
binary_format/embed_pck=true
'''
    (ROOT / 'client/export_presets.cfg').write_text(presets)
    return dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                JAVA_HOME=str(java), ANDROID_HOME=str(sdk))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=['android', 'web', 'linux', 'check'])
    parser.add_argument('--toolchain', type=Path, default=ROOT / '.toolchain')
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk'))))
    parser.add_argument('--bootstrap', action='store_true', help='Fetch/verify official tools if not configured')
    args = parser.parse_args()
    cache = args.toolchain.resolve()
    config_file = cache / 'toolchain.json'
    tools = bootstrap(cache) if args.bootstrap or not config_file.exists() else json.loads(config_file.read_text())
    env = configure(tools, cache, args.sdk.resolve())
    cmd = [tools['engine'], '--headless', '--path', str(ROOT / 'client')]
    run_checked(cmd + ['--editor', '--import'], env, 'import')
    if args.target == 'check':
        run_checked(cmd + ['--quit-after', '120'], env, 'runtime')
        return
    names = {'android':'Android', 'web':'Web', 'linux':'Linux'}
    dest = {'android':ROOT/'builds/aster-vale-debug.apk', 'web':ROOT/'builds/web/index.html',
            'linux':ROOT/'builds/linux/aster-vale.x86_64'}[args.target]
    dest.parent.mkdir(parents=True, exist_ok=True)
    run_checked(cmd + ['--export-debug', names[args.target], str(dest)], env, args.target + '-export')
    print('Exported', dest)

if __name__ == '__main__':
    main()
