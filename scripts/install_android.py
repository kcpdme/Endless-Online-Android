#!/usr/bin/env python3
"""Install a full signed APK update, preserve app data, verify version and bytes."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.cloudgameboy.astervale'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', type=Path, default=Path.home() / 'Android/Sdk/platform-tools/adb')
    parser.add_argument('--device')
    parser.add_argument('--apk', type=Path, default=ROOT / 'builds/aster-vale-release.apk')
    args = parser.parse_args()
    def adb(*parts):
        return subprocess.check_output([str(args.adb), *parts], text=True, timeout=240).strip()
    device = args.device
    if not device:
        devices = [line.split()[0] for line in adb('devices').splitlines()[1:] if len(line.split()) >= 2 and line.split()[1] == 'device']
        if len(devices) != 1: parser.error('Connect one Android device, or select --device SERIAL')
        device = devices[0]
    def shell(*parts): return adb('-s', device, 'shell', *parts)
    before = shell('dumpsys', 'package', PACKAGE)
    stamps = re.findall(r'firstInstallTime=(.+)', before)
    # Incremental install can report success before a usable package is available.
    # A full update never uninstalls or clears the existing application.
    print(adb('-s', device, 'install', '--no-incremental', '-r', '--user', '0', str(args.apk.resolve())))
    after = shell('dumpsys', 'package', PACKAGE)
    assert 'versionName=' in after, 'Installed package unavailable'
    if stamps:
        assert re.findall(r'firstInstallTime=(.+)', after) == stamps, 'Android changed firstInstallTime; inspect data preservation'
    path = shell('pm', 'path', '--user', '0', PACKAGE).removeprefix('package:')
    expected = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    assert shell('sha256sum', path).split()[0] == expected, 'Installed APK differs from release'
    for line in after.splitlines():
        if 'versionCode=' in line or 'versionName=' in line: print(line.strip())
    print('Verified installed APK SHA256:', expected)
    if stamps: print('Original firstInstallTime preserved; full update completed.')

if __name__ == '__main__': main()
