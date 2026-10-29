#!/usr/bin/env python3
"""Private, opt-in map-art pilot; never overwrites installed content.

Prepare crops, run npc-smoothing/smooth-player-items.mjs on jobs.json, then pack.
All intermediate and comparison assets stay outside the shipped client.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'pack'])
    parser.add_argument('--map', type=int, default=15)
    parser.add_argument('--output', type=Path, default=ROOT/'work/map-pilot')
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if args.mode == 'prepare':
        manifest = json.loads((ROOT/'client/content/manifest.json').read_text())
        world = next(w for w in (json.loads(p.read_text()) for p in (ROOT/'client/content/maps').glob('*.json')) if w['id'] == args.map)
        required = {(3, world['fill_tile'])} if world['fill_tile'] else set()
        for layer, entries in world['layers'].items():
            required.update((int(manifest['layer_gfx'].get(layer, 3)), int(r['id'])) for r in entries if r['id'])
        (folder/'crops').mkdir(exist_ok=True)
        crops, records = {}, {}
        floor_keys = {f'3:{r["id"]}' for r in world['layers']['ground'] if r['id']}
        if world['fill_tile']: floor_keys.add(f'3:{world["fill_tile"]}')
        for gfx, ident in sorted(required):
            key = f'{gfx}:{ident}'
            spec = manifest['graphics'][key]
            source = ROOT/'client'/spec['path'].removeprefix('res://')
            image = Image.open(source).convert('RGBA')
            frames = 4 if (gfx == 3 and image.width >= 128) or (gfx == 6 and image.width > 68) else 1
            assert image.width % frames == 0
            ids = []
            for frame in range(frames):
                name = f'g{gfx}_{ident}_{frame}'
                width = image.width//frames
                image.crop((frame*width, 0, (frame+1)*width, image.height)).save(folder/'crops'/f'{name}.png')
                crops[name] = {'preserve_black': False}
                ids.append(name)
            records[key] = {'ids': ids, 'native_size': list(image.size), 'source_bytes': source.stat().st_size,
                            'original_path': str(source), 'floor': key in floor_keys}
        (folder/'jobs.json').write_text(json.dumps({'crops': crops, 'records': records, 'map_id': args.map, 'name': world['name']}, indent=2)+'\n')
        print(f"Prepared {len(records)} environment graphics / {len(crops)} independent animation frames.")
        return
    jobs = json.loads((folder/'jobs.json').read_text())
    (folder/'enhanced').mkdir(exist_ok=True)
    graphics, encoded, decoded = {}, 0, 0
    for key, spec in jobs['records'].items():
        width, height = spec['native_size']
        image = Image.new('RGBA', (width*2, height*2))
        for index, name in enumerate(spec['ids']):
            frame = Image.open(folder/'scaled'/f'{name}.png').convert('RGBA')
            frame = frame.convert('RGBa').resize((frame.width//2, frame.height//2), Image.Resampling.LANCZOS).convert('RGBA')
            image.paste(frame, (index*width*2//len(spec['ids']), 0))
        if spec['floor']:
            # Adjacent isometric diamonds must keep exactly complementary
            # coverage. Blending both translucent edges creates a dark grid.
            native = Image.open(spec['original_path']).convert('RGBA')
            alpha = native.getchannel('A')
            border = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(3)))
            image = Image.composite(native.resize(image.size, Image.Resampling.NEAREST), image,
                                    border.resize(image.size, Image.Resampling.NEAREST))
            image.putalpha(alpha.resize(image.size, Image.Resampling.NEAREST))
        destination = folder/'enhanced'/(key.replace(':', '_')+'.webp')
        image.save(destination, lossless=spec['floor'], quality=90, method=6)
        encoded += destination.stat().st_size
        decoded += image.width*image.height*4
        graphics[key] = {'path': str(destination), 'native_size': spec['native_size'], 'floor': spec['floor']}
    report = {'map_id': jobs['map_id'], 'map_name': jobs['name'], 'graphics': len(graphics),
              'animation_frames': len(jobs['crops']), 'method': 'xBRZ 4x; premultiplied-alpha Lanczos to 2x; WebP 90 / lossless floors',
              'original_png_bytes': sum(r['source_bytes'] for r in jobs['records'].values()),
              'enhanced_encoded_bytes': encoded, 'enhanced_decoded_bytes': decoded,
              'floor_seams': 'Original boundary colour and alpha footprints; lossless floor textures; nearest floor sampling',
              'installed_assets_changed': False, 'apk_growth_bytes': 0}
    (folder/'preview.json').write_text(json.dumps({'graphics': graphics, 'report': report}, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
