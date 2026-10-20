#!/usr/bin/env python3
"""Preserve a complete native bundle and its measured ELF/dependency receipts."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile

bundle = pathlib.Path(sys.argv[1]).resolve(strict=True)
evidence = pathlib.Path(sys.argv[2]).resolve(strict=True)
assert str(bundle) == '/home/runner/bdk-audio-056-jammy/build/linux/x64/debug/bundle'
assert pathlib.Path('/.bdk-owned-jammy-root').read_text().strip() == 'jammy-056-20261016'
manifest, elfs, dependencies = [], [], []
missing = False
for path in sorted(bundle.rglob('*')):
    stat = path.lstat()
    item = {'path': path.relative_to(bundle).as_posix(), 'mode': oct(stat.st_mode & 0o7777)}
    if path.is_symlink():
        item.update(type='symlink', target=os.readlink(path))
        assert path.resolve().is_relative_to(bundle), 'Escaping bundle symlink'
    elif path.is_dir():
        item.update(type='directory')
    elif path.is_file():
        data = path.read_bytes()
        item.update(type='file', size=len(data), sha256=hashlib.sha256(data).hexdigest())
        if data[:4] == b'\x7fELF':
            header = subprocess.check_output(['readelf', '-h', str(path)], text=True)
            versions = subprocess.check_output(['readelf', '--version-info', str(path)], text=True)
            needed = versions.split('Version needs section', 1)[-1] if 'Version needs section' in versions else ''
            dynamic = subprocess.check_output(['readelf', '-d', str(path)], text=True)
            ldd = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
            dependencies.append(str(path) + '\n' + ldd.stdout + ldd.stderr)
            missing = missing or ldd.returncode != 0 or 'not found' in ldd.stdout
            machine = re.search(r'Machine:\s*(.*)', header).group(1)
            assert machine == 'Advanced Micro Devices X86-64', machine
            requirements = {prefix: sorted(set(re.findall(r'Name: ' + prefix + r'_([0-9.]+)', needed)),
                           key=lambda value: tuple(map(int, value.split('.'))))
                            for prefix in ('GLIBC', 'GLIBCXX', 'CXXABI')}
            elfs.append(dict(path=item['path'], sha256=item['sha256'], machine=machine,
                             requirements=requirements,
                             needed=re.findall(r'\(NEEDED\).*\[(.*?)\]', dynamic)))
            (evidence / ('elf-' + path.name + '.txt')).write_text(header + dynamic + versions)
    else:
        raise ValueError('Unsupported bundle entry: ' + str(path))
    manifest.append(item)
(evidence / 'bundle-manifest.json').write_text(json.dumps(manifest, indent=2))
(evidence / 'elf-abi.json').write_text(json.dumps(elfs, indent=2))
(evidence / 'ldd.txt').write_text('\n'.join(dependencies))
assert not missing, 'At least one bundled ELF has an unresolved runtime dependency'
archive = evidence / 'bdk-audio-0.5.6-linux-jammy-x64-debug-preview.tar.gz'
assert not archive.exists(), 'Never overwrite an earlier exported bundle'
with tarfile.open(archive, 'w:gz') as output:
    for path in sorted(bundle.rglob('*')):
        output.add(path, arcname=path.relative_to(bundle).as_posix(), recursive=False)
maxima = {prefix: max((version for elf in elfs for version in elf['requirements'][prefix]),
                     key=lambda value: tuple(map(int, value.split('.'))), default=None)
          for prefix in ('GLIBC', 'GLIBCXX', 'CXXABI')}
result = {'elf_count': len(elfs), 'bundle_entries': len(manifest), 'maxima': maxima,
          'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'archive_size': archive.stat().st_size, 'unresolved_dependencies': missing}
(evidence / 'bundle-summary.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
