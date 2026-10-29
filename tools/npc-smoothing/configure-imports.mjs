import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const [directory] = process.argv.slice(2);
if (!directory) throw new Error('Usage: configure-imports.mjs IMPORTED_ATLAS_DIRECTORY');
let count = 0;
for (const file of readdirSync(directory)) {
  if (!/^npc\d+_2x\.png\.import$/.test(file)) continue;
  const path = join(directory, file);
  const lossless = ['npc134_2x.png.import', 'npc154_2x.png.import'].includes(file);
  const original = readFileSync(path, 'utf8');
  const configured = original.replace(/^compress\/mode=\d+$/m, `compress/mode=${lossless ? 0 : 1}`)
    .replace(/^compress\/lossy_quality=[\d.]+$/m, 'compress/lossy_quality=0.90');
  if (configured !== original) writeFileSync(path, configured);
  count += 1;
}
if (count === 0) throw new Error('Run Godot import before configuring atlas compression');
console.log(`Configured ${count} atlases: WebP quality 0.90; approved painted pilot lossless`);
