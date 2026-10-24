#!/usr/bin/env python3
"""Stage character-only copies and publish reviewed releases without touching Classic."""
import argparse
import copy
import hashlib
import json
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return json.loads(path.read_text())

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def frames(data):
    if isinstance(data, dict):
        if 'path' in data and 'region' in data:
            yield data
        else:
            for value in data.values():
                yield from frames(value)
    elif isinstance(data, list):
        for value in data:
            yield from frames(value)

def confined(base, path):
    result = path.resolve()
    if not result.is_relative_to(base.resolve()):
        raise ValueError('Asset path escapes its pack')
    return result

def local_resource(root, value):
    if not value.startswith('res://'):
        raise ValueError('Expected a project resource')
    return confined(root / 'client', root / 'client' / value.removeprefix('res://'))

def pack_dir(root, pack):
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,47}', pack):
        raise ValueError('Use a lowercase pack name')
    return root / 'client/art_packs' / pack

def stage(root, pack):
    target = pack_dir(root, pack)
    if target.exists():
        raise ValueError('Pack already exists; drafts and previous releases are never overwritten')
    manifest = read(root / 'client/content/manifest.json')
    layers = manifest['characters']['equipment_layers']['layers']
    paths = sorted({f['path'] for f in frames(layers)})
    sources = {p: local_resource(root, p) for p in paths}
    for path in sources.values():
        confined(root / 'client/content/characters', path)
        if not path.is_file(): raise ValueError(f'Missing Classic asset: {path.name}')
    backup = root / 'artifacts/graphics-backups' / ('classic-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    backup.mkdir(parents=True)
    shutil.copy2(root / 'client/content/manifest.json', backup / 'manifest.json')
    hashes = {}
    draft = copy.deepcopy(layers)
    try:
        for folder in ('source', 'draft', 'concepts'):
            (target / folder).mkdir(parents=True)
            (target / folder / '.gdignore').write_text('')
        for resource, source in sources.items():
            relative = source.relative_to(root / 'client/content')
            hashes[str(relative)] = digest(source)
            for base in (backup, target / 'source', target / 'draft'):
                dest = base / relative; dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
                dest.chmod(0o644 if base == target / 'draft' else 0o444)
        prefix = 'res://art_packs/' + pack + '/draft/'
        for frame in frames(draft): frame['path'] = prefix + frame['path'].removeprefix('res://content/')
        write(target / 'source/layers.json', layers)
        write(target / 'source/hashes.json', hashes)
        write(target / 'draft/layers.json', draft)
        write(target / 'draft/reviewed_layers.json', [])
        write(target / 'pack.json', dict(schema=1, id=pack, status='draft', layers={}))
        write(backup / 'hashes.json', hashes)
        write(target / 'source/baseline.json', dict(backup=str(backup.relative_to(root)), layer_sets=len(layers), files=len(paths), maps_copied=0))
        for base in (backup, target / 'source'):
            for path in base.rglob('*'):
                if path.is_file(): path.chmod(0o444)
    except Exception:
        # Only the new incomplete pack is removed; the baseline backup is retained.
        if target.exists(): shutil.rmtree(target)
        raise
    return verify(root, pack)

def verify(root, pack):
    target = pack_dir(root, pack)
    hashes = read(target / 'source/hashes.json')
    baseline = read(target / 'source/baseline.json')
    backup = confined(root / 'artifacts/graphics-backups', root / baseline['backup'])
    for relative, expected in hashes.items():
        for base in (root / 'client/content', target / 'source', backup):
            path = confined(base, base / relative)
            if not path.is_file() or digest(path) != expected:
                raise ValueError(f'Baseline verification failed: {path}')
    if digest(backup / 'manifest.json') != digest(root / 'client/content/manifest.json'):
        raise ValueError('Original manifest changed since this baseline; inspect before publishing')
    return dict(result='passed', pack=pack, **baseline, original_assets_unchanged=True)

def validate_layer(original, candidate, root, draft_root, images):
    if isinstance(original, dict):
        if not isinstance(candidate, dict): raise ValueError('Layer structure changed')
        if 'path' in original and 'region' in original:
            scale = candidate.get('pixel_scale', 1)
            region = candidate.get('region', [])
            path = confined(draft_root, local_resource(root, candidate['path']))
            if scale not in (1, 2, 3, 4) or len(region) != 4 or any(type(v) not in (int, float) or int(v) != v or v < 0 for v in region):
                raise ValueError('Invalid source scale or frame region')
            if region[2:] != [v * scale for v in original['region'][2:]] or candidate.get('offset', [0, 0]) != original.get('offset', [0, 0]):
                raise ValueError('Frame must preserve Classic logical size and foot anchor')
            if path not in images:
                with Image.open(path) as image:
                    if image.format != 'PNG' or image.mode != 'RGBA': raise ValueError('Use RGBA PNG with real transparency')
                    images[path] = image.size
            width, height = images[path]
            if region[0] + region[2] > width or region[1] + region[3] > height or max(width, height) > 8192:
                raise ValueError('Frame is outside its atlas or atlas exceeds 8192 pixels')
        else:
            for key, value in original.items(): validate_layer(value, candidate[key], root, draft_root, images)
    elif isinstance(original, list):
        if not isinstance(candidate, list) or len(original) != len(candidate): raise ValueError('Animation frame count changed')
        for a, b in zip(original, candidate): validate_layer(a, b, root, draft_root, images)
    elif original != candidate:
        raise ValueError('Animation or equipment metadata changed')

def publish(root, pack, release):
    verify(root, pack)
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,47}', release): raise ValueError('Invalid release name')
    target = pack_dir(root, pack); dest = target / 'releases' / release
    if dest.exists(): raise ValueError('A release is immutable; use a new release name')
    original = read(target / 'source/layers.json'); draft = read(target / 'draft/layers.json')
    reviewed = read(target / 'draft/reviewed_layers.json')
    if not isinstance(reviewed, list) or not reviewed or len(set(reviewed)) != len(reviewed): raise ValueError('List the completed, reviewed layer keys first')
    current = read(target / 'pack.json'); layers = copy.deepcopy(current.get('layers', {})); images = {}
    for key in reviewed:
        validate_layer(original[key], draft[key], root, target / 'draft', images)
        paths = {f['path'] for f in frames(draft[key])}
        old_paths = {f['path'] for f in frames(original[key])}
        if {digest(local_resource(root, p)) for p in paths} == {digest(local_resource(root, p)) for p in old_paths}:
            raise ValueError(f'{key} is still an unchanged Classic copy')
        layers[key] = copy.deepcopy(draft[key])
    dest.mkdir(parents=True)
    # Copy reviewed files only. Previously published layers retain their immutable release paths.
    for key in reviewed:
        for frame in frames(layers[key]):
            source = confined(target / 'draft', local_resource(root, frame['path']))
            asset = dest / 'assets' / source.relative_to(target / 'draft')
            asset.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, asset)
            frame['path'] = 'res://' + str(asset.relative_to(root / 'client'))
    descriptor = dict(schema=1, id=pack, status='ready', release=release, layers=layers)
    write(dest / 'pack.json', descriptor)
    pending = target / 'pack.pending.json'; write(pending, descriptor); os.replace(pending, target / 'pack.json')
    return dict(result='published', release=release, layers=len(layers), maps_changed=False)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['stage', 'verify', 'publish'])
    parser.add_argument('--pack', default='painted_v1'); parser.add_argument('--release')
    args = parser.parse_args()
    if args.action == 'publish' and not args.release: parser.error('--release is required')
    result = publish(ROOT, args.pack, args.release) if args.action == 'publish' else globals()[args.action](ROOT, args.pack)
    print(json.dumps(result, indent=2))

if __name__ == '__main__': main()
