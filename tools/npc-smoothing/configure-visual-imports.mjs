import { readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { createHash } from 'node:crypto';
const [directory, modesPath, templatePath] = process.argv.slice(2);
if (!templatePath) throw new Error('Usage: configure-visual-imports.mjs OUTPUT_DIRECTORY IMPORT_MODES.json EXISTING_TEXTURE.png.import');
const modes = JSON.parse(readFileSync(modesPath, 'utf8'));
const template = readFileSync(templatePath, 'utf8').replace(/^uid=.*\n/m, '');
for (const [source, lossless] of Object.entries(modes)) {
  const name = basename(source);
  const hash = createHash('md5').update(source).digest('hex');
  const destination = `res://.godot/imported/${name}-${hash}.ctex`;
  const configured = template.replace(/^path=.*$/m, `path="${destination}"`)
    .replace(/^source_file=.*$/m, `source_file="${source}"`)
    .replace(/^dest_files=.*$/m, `dest_files=["${destination}"]`)
    .replace(/^compress\/mode=\d+$/m, `compress/mode=${lossless ? 0 : 1}`)
    .replace(/^compress\/lossy_quality=[\d.]+$/m, 'compress/lossy_quality=0.90');
  writeFileSync(join(directory, `${name}.import`), configured);
}
console.log(`Configured ${Object.keys(modes).length} player/item atlases; exact black masks remain lossless`);
