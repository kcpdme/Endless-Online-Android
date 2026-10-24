#!/usr/bin/env python3
"""Reproducible Android APK/AAB, Linux or browser export. Never publishes."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import re
import zipfile
from bootstrap_godot import bootstrap

ROOT = Path(__file__).resolve().parents[1]
ANDROID_PACKAGE = 'com.cloudgameboy.astervale'
ANDROID_VERSION_CODE = 64
ANDROID_VERSION_NAME = '0.39.8'

def run_checked(command, env, name):
    """Godot can return zero for script errors, so inspect diagnostics as well."""
    logdir = ROOT / 'builds' / 'logs'
    logdir.mkdir(parents=True, exist_ok=True)
    log = logdir / (name + '.log')
    with log.open('w') as stream:
        log.chmod(0o600)
        result = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text(errors='replace')
    diagnostics = [line for line in output.splitlines() if re.search(r'(^|\s)(SCRIPT ERROR:|ERROR:)', line)]
    if result.returncode or diagnostics:
        summary = '\n'.join(output.splitlines()[-35:])
        for key in ('GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD',):
            if env.get(key): summary = summary.replace(env[key], '[redacted]')
        print(summary)
        raise RuntimeError(f'{name} failed (exit {result.returncode}); see {log}')
    print(f'{name}: passed; log {log}')

def quoted(value):
    return json.dumps(str(value))

def normalize_aab_manifest_order(path):
    """Keep the JAR manifest first so streaming and random-access verifiers agree.

    Godot appends signing entries. Moving entries preserves their bytes and
    signatures while allowing JarInputStream to verify the entire bundle.
    """
    with zipfile.ZipFile(path) as original:
        entries = original.infolist()
        manifest = 'META-INF/MANIFEST.MF'
        if entries[0].filename == manifest: return
        if manifest not in original.namelist(): raise RuntimeError('AAB is not signed')
        signing = [entry for entry in entries if entry.filename.startswith('META-INF/')]
        ordered = [original.getinfo(manifest)] + [entry for entry in signing if entry.filename != manifest]
        ordered += [entry for entry in entries if not entry.filename.startswith('META-INF/')]
        temporary = path.with_suffix('.ordered.aab')
        with zipfile.ZipFile(temporary, 'w') as output:
            for entry in ordered: output.writestr(entry, original.read(entry))
    temporary.replace(path)

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
exclude_filter="art_packs/*"
export_path="../builds/aster-vale-debug.apk"

[preset.0.options]
custom_template/debug={quoted(templates / 'android_debug.apk')}
custom_template/release={quoted(templates / 'android_release.apk')}
gradle_build/use_gradle_build=true
gradle_build/export_format=0
gradle_build/android_source_template={quoted(templates / "android_source.zip")}
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=true
version/code={ANDROID_VERSION_CODE}
version/name="{ANDROID_VERSION_NAME}"
package/unique_name="{ANDROID_PACKAGE}"
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
exclude_filter="art_packs/*"
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
exclude_filter="art_packs/*"
export_path="../builds/linux/aster-vale.x86_64"

[preset.2.options]
custom_template/debug={quoted(templates / 'linux_debug.x86_64')}
custom_template/release={quoted(templates / 'linux_release.x86_64')}
binary_format/embed_pck=true
'''
    # Both Android formats include the first-party Keystore plugin through Gradle.
    # The presets share their app identity, signing key and ABIs.
    android_options = presets.split('[preset.0.options]\n', 1)[1].split('[preset.1]', 1)[0]
    bundle_options = android_options.replace('gradle_build/export_format=0', 'gradle_build/export_format=1')
    presets += '''
[preset.3]
name="Android Bundle"
platform="Android"
runnable=false
export_filter="all_resources"
include_filter="*.json"
exclude_filter="art_packs/*"
export_path="../builds/aster-vale-release.aab"

[preset.3.options]
''' + bundle_options
    (ROOT / 'client/export_presets.cfg').write_text(presets)
    return dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                JAVA_HOME=str(java), ANDROID_HOME=str(sdk))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=['android', 'android-aab', 'web', 'linux', 'check'])
    parser.add_argument('--release', action='store_true', help='Sign an Android release; always enabled for AAB')
    parser.add_argument('--signing-config', type=Path, help='Private JSON with keystore path, alias and password; defaults to toolchain/release-signing.json')
    parser.add_argument('--toolchain', type=Path, default=ROOT / '.toolchain')
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk'))))
    parser.add_argument('--bootstrap', action='store_true', help='Fetch/verify official tools if not configured')
    args = parser.parse_args()
    cache = args.toolchain.resolve()
    config_file = cache / 'toolchain.json'
    tools = bootstrap(cache) if args.bootstrap or not config_file.exists() else json.loads(config_file.read_text())
    env = configure(tools, cache, args.sdk.resolve())
    release = args.release or args.target == 'android-aab'
    if release and args.target in ('android', 'android-aab'):
        signing_path = args.signing_config or cache / 'release-signing.json'
        signing = json.loads(signing_path.read_text())
        keystore = Path(signing['path']).expanduser().resolve()
        if not keystore.is_file(): raise RuntimeError('Release keystore is missing')
        env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(keystore),
                   GODOT_ANDROID_KEYSTORE_RELEASE_USER=signing['alias'],
                   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=signing['password'])
    cmd = [tools['engine'], '--headless', '--path', str(ROOT / 'client')]
    run_checked(cmd + ['--editor', '--import'], env, 'import')
    if args.target == 'check':
        run_checked(cmd + ['--quit-after', '120'], env, 'runtime')
        return
    if args.target in ('android','android-aab'):
        if not (ROOT/'client/android/build/build.gradle').exists():
            run_checked(cmd+['--install-android-build-template','--editor','--quit'],env,'android-template')
        from android_native import stage
        stage()
    names = {'android':'Android', 'android-aab':'Android Bundle', 'web':'Web', 'linux':'Linux'}
    dest = {'android':ROOT/('builds/aster-vale-release.apk' if release else 'builds/aster-vale-debug.apk'),
            'android-aab':ROOT/'builds/aster-vale-release.aab', 'web':ROOT/'builds/web/index.html',
            'linux':ROOT/'builds/linux/aster-vale.x86_64'}[args.target]
    dest.parent.mkdir(parents=True, exist_ok=True)
    export_args = ['--export-release' if release else '--export-debug', names[args.target], str(dest)]
    if args.target == 'android-aab' and not (ROOT / 'client/android/build/build.gradle').is_file():
        export_args.insert(0, '--install-android-build-template')
    run_checked(cmd + export_args, env, args.target + '-export')
    if args.target == 'android-aab': normalize_aab_manifest_order(dest)
    print('Exported', dest)

if __name__ == '__main__':
    main()
