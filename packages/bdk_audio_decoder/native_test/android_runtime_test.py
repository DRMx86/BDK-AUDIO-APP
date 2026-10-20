"""Bounded offline QA on the explicitly authorized decoder diagnostic target.

No installation, UI, settings, audio device, BLE, or serial operations. Provision
the opt-in CLI, shared library, and generated fixtures into REMOTE first.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
REMOTE = '/data/local/tmp/bdk-decoder-qa-20261016'
parser = argparse.ArgumentParser()
parser.add_argument('--adb', required=True)
parser.add_argument('--serial', required=True, choices=['9125299103B7'])
args = parser.parse_args()
results = []
receipt = ROOT / 'build/android-runtime-green.json'


def run(name, rate=None, start=0, count=0, compare=False, success=True):
    command = (f'LD_LIBRARY_PATH={REMOTE} timeout -k 2 40 '
               f'{REMOTE}/bdk_decoder_qa {REMOTE}/{name}')
    if rate is not None:
        command += f' {rate} {start} {count}'
        if compare:
            command += ' --compare'
    begin = time.monotonic()
    proc = subprocess.run([args.adb, '-s', args.serial, 'shell', command],
                          capture_output=True, text=True, timeout=45)
    output = proc.stdout + proc.stderr
    passed = proc.returncode == 0 if success else proc.returncode not in (0, 124, 137)
    if rate is not None and success:
        match = re.search(r'decode code=0 .*written=(\d+) nonzero=(\d+).*guards=1', output)
        passed &= bool(match) and int(match[1]) == count and int(match[2]) > 0
    if not success and 'decode code=' in output:
        passed &= 'written=0 ' in output
    results.append(dict(file=name, rate=rate, start=start, count=count,
                        compare=compare, expectedSuccess=success,
                        exitCode=proc.returncode, passed=passed,
                        seconds=round(time.monotonic() - begin, 3), output=output))
    receipt.write_text(json.dumps(dict(serial=args.serial, cases=results), indent=2), encoding='utf8')
    print(f'{"PASS" if passed else "FAIL"} {name} {rate} {start} {count}', flush=True)
    if not passed:
        print(output, flush=True)
        raise AssertionError(results[-1])
    return output


formats = ['ramp.wav', 'chunks.wav', 'float.wav', 'extensible.wav',
           'real.mp3', 'real.flac', 'real.m4a', 'real.aac', 'tagged.aac',
           'real.ogg', 'cache.audio', 'stereo.m4a']
for name in formats:
    probe = run(name)
    metadata = re.search(r'probe code=0 rate=(\d+) channels=(\d+) frames=(\d+)', probe)
    assert metadata, probe
    source_rate, channels, frames = map(int, metadata.groups())
    assert frames > 0 and channels > 0
    for rate in [22050, 16000, 11025, 8000]:
        available = frames * rate // source_rate
        run(name, rate, 0, available)
        run(name, rate, rate, 1000, compare=True)
        run(name, rate, available - 1000, 1000, compare=True)
    local = ROOT / 'build/fixtures' / name
    results[-1]['sourceSha256'] = hashlib.sha256(local.read_bytes()).hexdigest()

# Later selected windows must preserve decoder history and output-frame indices.
for rate in [22050, 16000, 11025, 8000]:
    run('long.m4a', rate, rate * 3, 1000, compare=True)
    run('long.m4a', rate, rate * 6 - 1000, 1000,
        compare=rate * 6 <= 102378)

for name in ['cut-real.m4a', 'cut-real.aac', 'cut-real.ogg',
             'cut-real.mp3', 'cut-real.flac', 'truncated.wav', 'invalid.bin']:
    run(name, 16000, 31000, 1000, success=False)

run('real.m4a', 22050, 44100, 1, success=False)
run('real.m4a', 44100, 0, 100, success=False)
run('long120.m4a', 22050, 22050 * 110, 1000)
print(f'{len(results)} offline Android C ABI cases passed; receipt: {receipt}', flush=True)
