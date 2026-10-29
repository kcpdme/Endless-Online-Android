import { readFileSync, writeFileSync } from 'node:fs';
const [manifestPath, outputPath] = process.argv.slice(2);
if (!outputPath) throw new Error('Usage: prepare.mjs MANIFEST.json OUTPUT.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const sources = {};
for (const [gid, original] of Object.entries(manifest.characters.npcs)) {
  const frames = [];
  for (const direction of ['south', 'north']) {
    for (const state of ['idle', 'frames', 'attack']) {
      const raw = original[state][direction];
      (Array.isArray(raw) ? raw : [raw]).forEach((frame, index) => frames.push({ direction, state, index, frame }));
    }
  }
  sources[gid] = { original, frames };
}
writeFileSync(outputPath, JSON.stringify(sources, null, 2) + '\n');
console.log(`Prepared ${Object.keys(sources).length} NPC sprite definitions`);
