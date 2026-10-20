// Rasterizes the app's code-native SVG master, never an existing bitmap.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.BDK_SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '..');
const check = process.argv.includes('--check');
const master = fs.readFileSync(path.join(root, 'assets/branding/bdk-mark.svg'), 'utf8');
// Keep adaptive foreground framing explicit: silently exporting the opaque tile
// would hide the musical note under platform masks after a master edit.
for (const fragment of [
  '<rect width="100" height="100" fill="url(#surface)"/>',
  'translate(10 8) scale(.84)',
  'id="eighth-note"',
]) {
  if (!master.includes(fragment)) throw new Error(`Unsupported brand master: ${fragment}`);
}
const foreground = master
  .replace('<rect width="100" height="100" fill="url(#surface)"/>', '')
  .replace('translate(10 8) scale(.84)', 'translate(20.55 19) scale(.62)');
const rounded = master.replace(
  '<rect width="100" height="100" fill="url(#surface)"/>',
  '<rect x="6" y="6" width="88" height="88" rx="20" fill="url(#surface)"/>',
);
const round = master.replace(
  '<rect width="100" height="100" fill="url(#surface)"/>',
  '<rect width="100" height="100" rx="50" fill="url(#surface)"/>',
);

async function png(svg, size, opaque = false) {
  const renderer = sharp(Buffer.from(svg)).resize(size, size);
  if (opaque) renderer.removeAlpha();
  return renderer.png().toBuffer();
}

function output(relative, data) {
  const target = path.join(root, relative);
  if (check) {
    if (!fs.existsSync(target) || !fs.readFileSync(target).equals(data)) {
      throw new Error(`Icon export differs: ${relative}`);
    }
  } else {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, data);
  }
}

async function main() {
  for (const [density, size] of Object.entries({mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192})) {
    const folder = `android/app/src/main/res/mipmap-${density}`;
    output(`${folder}/ic_launcher.png`, await png(master, size, true));
    output(`${folder}/ic_launcher_round.png`, await png(round, size));
    output(`${folder}/ic_launcher_foreground.png`, await png(foreground, size * 2.25));
  }
  for (const platform of ['ios', 'macos']) {
    const folder = `${platform}/Runner/Assets.xcassets/AppIcon.appiconset`;
    const manifest = JSON.parse(fs.readFileSync(path.join(root, folder, 'Contents.json'), 'utf8'));
    for (const entry of manifest.images) {
      const size = Number(entry.size.split('x')[0]) * Number(entry.scale.replace('x', ''));
      output(`${folder}/${entry.filename}`, await png(platform === 'macos' ? rounded : master, size, platform === 'ios'));
    }
  }
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const frames = await Promise.all(sizes.map(size => png(rounded, size)));
  const header = Buffer.alloc(6 + 16 * sizes.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((size, index) => {
    const position = 6 + index * 16;
    header[position] = size === 256 ? 0 : size;
    header[position + 1] = header[position];
    header.writeUInt16LE(1, position + 4);
    header.writeUInt16LE(32, position + 6);
    header.writeUInt32LE(frames[index].length, position + 8);
    header.writeUInt32LE(offset, position + 12);
    offset += frames[index].length;
  });
  output('windows/runner/resources/app_icon.ico', Buffer.concat([header, ...frames]));
  output('assets/branding/bdk-mark.png', await png(master, 512, true));
  output('linux/resources/com.bdkaudio.bdk_audio.png', await png(master, 512, true));
  // Keep the Apple launch view on the same vector master as its app icon.
  for (const [scale, size] of [[1, 112], [2, 224], [3, 336]]) {
    output(`ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage${scale === 1 ? '' : `@${scale}x`}.png`, await png(master, size, true));
  }
  process.stdout.write(`${check ? 'Verified' : 'Generated'} BDK launcher exports for five platforms.\n`);
}

main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
