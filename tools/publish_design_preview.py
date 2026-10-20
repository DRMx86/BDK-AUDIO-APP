"""Publish the reviewed UI with source-backed rendering to the existing preview."""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT.parent / "BDK-AUDIO-APP-main/.superpowers/brainstorm/406-1792150437/content"
parser=argparse.ArgumentParser()
parser.add_argument('--version',default='v10')
args=parser.parse_args()
if not re.fullmatch(r'v[0-9]+',args.version):parser.error('Version must be v followed by digits')
html = (ROOT / "docs/ui-work/eq-and-sound-options.html").read_text(encoding="utf-8")
start = html.index(" const rgb=")
end = html.index(" function theme(", start)
bridge = (ROOT / "tools/firmware_preview.js").read_text(encoding="utf-8")
html = html[:start] + bridge + "\n" + html[end:]
css=(ROOT/'tools/firmware_preview.css').read_text(encoding='utf-8')
html=html.replace('</style>',css+'\n</style>')
html = html.replace('aria-label="Simulated speaker light effect with soft diffusion"',
                    'aria-label="Firmware light effect rendered with simulated audio and soft diffusion"')
output = CONTENT / f"bdk-product-design-{args.version}.html"
output.write_text(html, encoding="utf-8")
print(output)
