"""Read only BDK custom EQ entries from the original debuggable Android app.

No app installation, settings, BLE, audio, serial or firmware operations. ADB
run-as is refused by Android for non-debuggable builds; this tool never roots or
works around that boundary. Raw preferences are not saved or printed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

MAXIMUM_BYTES = 256 * 1024
KEY = re.compile(r'custom_(?:preset_)?[123]_(?:name|bass|mid|treble)\Z')


def curate(raw: bytes) -> bytes:
    if not raw or len(raw) > MAXIMUM_BYTES or re.search(br'<!\s*(?:DOCTYPE|ENTITY)\b', raw, re.I):
        raise ValueError('Invalid or oversized Android preferences document.')
    root = ET.fromstring(raw)
    if root.tag != 'map':
        raise ValueError('Not an Android preferences document.')
    values = {}
    for element in root:
        key = element.get('name', '')
        if not KEY.fullmatch(key):
            continue
        if key in values or list(element):
            raise ValueError('Duplicate or nested preset entry.')
        if key.endswith('_name') and element.tag == 'string':
            value = element.text or ''
        elif not key.endswith('_name') and element.tag == 'int':
            value = int(element.get('value', ''))
            if not 0 <= value <= 100:
                raise ValueError('Android EQ value is outside 0..100.')
        else:
            raise ValueError('Invalid preset value type.')
        values[key] = value
    result = json.dumps({'format': 'bdk-android-prefs', 'version': 1,
                         'preferences': values}, ensure_ascii=False, indent=2).encode('utf-8')
    if len(result) > MAXIMUM_BYTES:
        raise ValueError('Preset backup exceeds its import size limit.')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, choices=['9125299103B7'])
    parser.add_argument('--adb', default=str(Path(os.environ.get('LOCALAPPDATA', '')) /
                                           'Android/Sdk/platform-tools/adb.exe'))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Output already exists; choose a new backup filename.')
    # head bounds the device-side read as well as the captured stdout. Never
    # shell-interpolate an app name/path, user filename or command.
    proc = subprocess.run([args.adb, '-s', args.serial, 'exec-out', 'run-as',
                           'com.example.myspeaker', 'head', '-c', str(MAXIMUM_BYTES + 1),
                           'shared_prefs/BDKAudioPrefs.xml'],
                          capture_output=True, timeout=15)
    if proc.returncode:
        raise SystemExit('Could not read original app preferences. The app must be debuggable and contain saved settings.')
    try:
        backup = curate(proc.stdout)
    except (ValueError, ET.ParseError) as error:
        raise SystemExit(f'No backup written: {error}') from error
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('xb') as stream:
        stream.write(backup)
    values = json.loads(backup)['preferences']
    print(json.dumps({'output': str(args.output.resolve()), 'presetFields': len(values),
                      'bytes': len(backup), 'sha256': hashlib.sha256(backup).hexdigest()}))


if __name__ == '__main__':
    main()
