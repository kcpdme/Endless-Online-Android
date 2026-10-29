#!/usr/bin/env python3
"""Reuse private xBRZ working images for an opt-in 4x player-art comparison.

No original/installed artwork is replaced and no image generation API is used.
Requires the previous player-item smoothing work folder and Pillow.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=Path('work/player-item-smoothing'))
    parser.add_argument('--output', type=Path, default=Path('work/zoom-pilot'))
    parser.add_argument('--pack', type=Path, default=Path('client/content/visual_enhanced/pack.json'))
    args = parser.parse_args()
    jobs = json.loads((args.work / 'jobs.json').read_text())
    pack = json.loads(args.pack.read_text())
    required = json.loads((args.output / 'required-frames.json').read_text())
    images, frames, finished = {}, {}, {}
    decoded = encoded = baseline_encoded = 0
    destination = args.output / '4x'
    destination.mkdir(exist_ok=True)
    for key in required:
        job = jobs['frames'][key]
        patch = job['id']
        if patch not in finished:
            image = Image.open(args.work / 'scaled' / f'{patch}.png').convert('RGBA')
            spec = jobs['crops'][patch]
            if spec['preserve_black']:
                source = Image.open(args.work / 'crops' / f'{patch}.png').convert('RGBA')
                draw = ImageDraw.Draw(image)
                for y in range(source.height):
                    for x in range(source.width):
                        r, g, b, a = source.getpixel((x, y))
                        if r == g == b == 0 and a:
                            draw.rectangle((x * 4, y * 4, x * 4 + 3, y * 4 + 3), fill=(0, 0, 0, a))
            output = destination / f'{patch}.webp'
            image.save(output, lossless=spec['preserve_black'], quality=90, method=6)
            baseline = destination / f'{patch}-2x-reference.webp'
            image.resize((image.width // 2, image.height // 2), Image.Resampling.LANCZOS).save(
                baseline, lossless=spec['preserve_black'], quality=90, method=6)
            baseline_encoded += baseline.stat().st_size
            encoded += output.stat().st_size
            decoded += image.width * image.height * 4
            # Measure final compressed pixels, as the runtime does.
            used = Image.open(output).getchannel('A').getbbox() or (0, 0, 0, 0)
            path = 'pilot4x://' + patch
            finished[patch] = {'path': path, 'region': [0, 0, image.width, image.height],
                               'visible_bounds': [used[0], used[1], used[2] - used[0], used[3] - used[1]]}
            images[path] = str(output.resolve())
        pose = pack['poses'][pack['frames'][key][0]]
        lookup = pose['path'] + '|%d,%d,%d,%d' % tuple(pose['region'])
        if lookup in frames:
            assert frames[lookup] == finished[patch], 'Canonical pose mismatch'
        frames[lookup] = finished[patch]
    report = {'required_frames': len(required), 'unique_patches': len(finished),
              'decoded_4x_bytes': decoded, 'encoded_4x_bytes': encoded,
              'encoded_2x_reference_bytes': baseline_encoded,
              'decoded_4x_vs_2x_ratio': 4, 'full_catalog_extrapolation': False,
              'method': 'Existing xBRZ 4x working pixels; native masks preserved; WebP 90/lossless masks',
              'installed_assets_changed': False}
    (args.output / 'high-res.json').write_text(json.dumps({'frames': frames, 'images': images}))
    (args.output / 'art-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
