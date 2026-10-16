#!/usr/bin/env python3
"""Fetch the pinned official Godot build and verify its published SHA-512 hashes."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen
import zipfile

VERSION = '4.7.2-stable'
ENGINE = f'Godot_v{VERSION}_linux.x86_64.zip'
TEMPLATES = f'Godot_v{VERSION}_export_templates.tpz'
BASE = f'https://github.com/godotengine/godot/releases/download/{VERSION}/'
WANTED = {'android_debug.apk', 'android_release.apk', 'web_debug.zip',
          'web_release.zip', 'web_nothreads_debug.zip', 'web_nothreads_release.zip',
          'linux_debug.x86_64', 'linux_release.x86_64', 'version.txt'}

def download(cache: Path, name: str):
    destination = cache / name
    if destination.exists():
        return destination
    print('Downloading', name, flush=True)
    temporary = destination.with_suffix(destination.suffix + '.part')
    with urlopen(Request(BASE + name, headers={'User-Agent': 'AsterVale-build'}), timeout=60) as source:
        with temporary.open('wb') as target:
            while chunk := source.read(4 * 1024 * 1024):
                target.write(chunk)
    temporary.replace(destination)
    return destination

def bootstrap(cache: Path):
    cache.mkdir(parents=True, exist_ok=True)
    checksum_path = download(cache, 'SHA512-SUMS.txt')
    checksums = {line.split()[-1].lstrip('*'): line.split()[0]
                 for line in checksum_path.read_text().splitlines() if len(line.split()) >= 2}
    for name in (ENGINE, TEMPLATES):
        path = download(cache, name)
        digest = hashlib.sha512()
        with path.open('rb') as source:
            while chunk := source.read(4 * 1024 * 1024):
                digest.update(chunk)
        if digest.hexdigest() != checksums.get(name):
            raise RuntimeError(f'Checksum mismatch: {name}; remove the cached file and retry')
        print('Verified', name, flush=True)
    engine = cache / 'godot' / f'Godot_v{VERSION}_linux.x86_64'
    if not engine.exists():
        with zipfile.ZipFile(cache / ENGINE) as archive:
            engine.parent.mkdir(exist_ok=True)
            engine.write_bytes(archive.read(engine.name))
    engine.chmod(0o755)
    template_dir = cache / 'export' / 'templates'
    template_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(cache / TEMPLATES) as archive:
        for name in archive.namelist():
            if Path(name).name in WANTED:
                destination = template_dir / Path(name).name
                if not destination.exists():
                    destination.write_bytes(archive.read(name))
                if '.x86_64' in destination.name:
                    destination.chmod(0o755)
    config = {'version': VERSION, 'engine': str(engine), 'templates': str(template_dir)}
    (cache / 'toolchain.json').write_text(json.dumps(config, indent=2))
    return config

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path(__file__).resolve().parents[1] / '.toolchain')
    args = parser.parse_args()
    print(json.dumps(bootstrap(args.cache.resolve()), indent=2))
