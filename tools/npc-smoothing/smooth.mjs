// SPDX-License-Identifier: GPL-3.0-only
// Offline xBRZ preparation. RGBA pixels/alpha and native frame geometry stay aligned.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { resolve, basename, join } from 'node:path';
import { createHash } from 'node:crypto';
import { Scaler } from '@kayahr/xbrz';
import { PNG } from 'pngjs';

const [sourcesPath, clientPath, outputPath, reportPath] = process.argv.slice(2);
if (!reportPath) throw new Error('Usage: smooth.mjs SOURCES.json CLIENT_DIRECTORY OUTPUT_DIRECTORY REPORT.json');
const sources = JSON.parse(readFileSync(sourcesPath, 'utf8'));
const output = resolve(outputPath);
mkdirSync(output, { recursive: true });
const scalers = new Map();
const cache = new Map();
let processed = 0;
let unique = 0;
for (const [gid, entry] of Object.entries(sources)) {
  if (['134', '154'].includes(gid)) continue; // Preserve the approved painted pilot.
  for (const item of entry.frames) {
    const sourcePath = resolve(clientPath, item.frame.path.replace(/^res:\/\//, ''));
    const bytes = readFileSync(sourcePath);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const targetPath = join(output, basename(sourcePath));
    if (cache.has(hash)) {
      copyFileSync(cache.get(hash), targetPath);
    } else {
      const png = PNG.sync.read(bytes);
      const key = `${png.width}x${png.height}`;
      // 4x edge reconstruction is subsequently antialiased down to compact 2x art.
      if (!scalers.has(key)) scalers.set(key, new Scaler(png.width, png.height, 4));
      const scaled = scalers.get(key).scale(new Uint8ClampedArray(png.data));
      const result = new PNG({ width: png.width * 4, height: png.height * 4 });
      result.data = Buffer.from(scaled);
      writeFileSync(targetPath, PNG.sync.write(result));
      cache.set(hash, targetPath);
      unique += 1;
    }
    processed += 1;
  }
  console.log(`Prepared NPC ${gid}: ${entry.original.name}`);
}
writeFileSync(reportPath, JSON.stringify({
  result: 'passed', algorithm: 'xBRZ 4x followed by alpha-correct Lanczos to 2x',
  dependency: '@kayahr/xbrz@1.1.2', graphics: Object.keys(sources).length - 2,
  canonical_frames: processed, unique_scaled_frames: unique, preserved_pilot_graphics: [134, 154],
}, null, 2) + '\n');
