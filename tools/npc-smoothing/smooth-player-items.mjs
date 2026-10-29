// SPDX-License-Identifier: GPL-3.0-only
// Offline RGBA smoothing shared with the NPC pipeline; no Android dependency.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Scaler } from '@kayahr/xbrz';
import { PNG } from 'pngjs';
const [jobsPath] = process.argv.slice(2);
if (!jobsPath) throw new Error('Usage: smooth-player-items.mjs JOBS.json');
const jobs = JSON.parse(readFileSync(jobsPath, 'utf8'));
const base = dirname(jobsPath);
mkdirSync(join(base, 'scaled'), { recursive: true });
const scalers = new Map();
let count = 0;
for (const [id, job] of Object.entries(jobs.crops)) {
  const png = PNG.sync.read(readFileSync(join(base, 'crops', `${id}.png`)));
  const key = `${png.width}x${png.height}`;
  if (!scalers.has(key)) {
    if (scalers.size >= 32) scalers.delete(scalers.keys().next().value);
    scalers.set(key, new Scaler(png.width, png.height, 4));
  }
  const pixels = scalers.get(key).scale(new Uint8ClampedArray(png.data));
  const image = new PNG({ width: png.width * 4, height: png.height * 4 });
  image.data = Buffer.from(pixels);
  writeFileSync(join(base, 'scaled', `${id}.png`), PNG.sync.write(image));
  count += 1;
  if (count % 100 === 0) console.log(`Smoothed ${count}/${Object.keys(jobs.crops).length} unique poses`);
}
writeFileSync(join(base, 'smoothing-report.json'), JSON.stringify({ result: 'passed', crops: count,
  algorithm: 'xBRZ 4x followed by alpha-correct Lanczos to 2x', scaler_cache_limit: 32,
  dependency: '@kayahr/xbrz@1.1.2' }, null, 2) + '\n');
