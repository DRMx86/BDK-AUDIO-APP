#!/usr/bin/env python3
"""Verify the reviewed source archive without trusting archive path/type metadata."""
import hashlib
import json
import pathlib
import sys
import tarfile

ARCHIVE_SHA256 = '0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50'


def safe_name(name):
    path = pathlib.PurePosixPath(name)
    return bool(name and not path.is_absolute() and str(path) == name
                and all(part not in ('..', '.git', 'artifacts', 'build', '.dart_tool')
                        for part in path.parts))


def checked_manifest(path):
    manifest = json.loads(pathlib.Path(path).read_text())
    if len(manifest) != 308 or not all(safe_name(p) for p in manifest):
        raise ValueError('Expected 308 safe reviewed file entries')
    return manifest


def verify_tree(manifest, destination):
    destination = pathlib.Path(destination).resolve(strict=True)
    for name, expected in manifest.items():
        path = destination / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(destination):
            raise ValueError('Unsafe or missing reviewed file: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Reviewed bytes changed: ' + name)
    return {'reviewed_files': len(manifest), 'matching_files': len(manifest),
            'source': str(destination), 'source_archive_sha256': ARCHIVE_SHA256}


def extract(archive, manifest, destination):
    archive = pathlib.Path(archive)
    destination = pathlib.Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError('Source extraction destination must be fresh')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Unexpected reviewed archive digest')
    with tarfile.open(archive, 'r:gz') as source:
        members = source.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)) or set(names) != set(manifest):
            raise ValueError('Archive paths must exactly match reviewed manifest')
        if not all(member.isfile() and safe_name(member.name) for member in members):
            raise ValueError('Archive contains nonregular or unsafe entries')
        destination.mkdir(parents=True)
        for member in members:
            output = destination / member.name
            output.parent.mkdir(parents=True, exist_ok=True)
            data = source.extractfile(member).read()
            if hashlib.sha256(data).hexdigest() != manifest[member.name]:
                raise ValueError('Archive member digest mismatch: ' + member.name)
            output.write_bytes(data)
            output.chmod(member.mode & 0o777)
    return verify_tree(manifest, destination)


if __name__ == '__main__':
    operation, manifest_path, destination, *extra = sys.argv[1:]
    manifest = checked_manifest(manifest_path)
    result = (extract(extra[0], manifest, destination) if operation == 'extract'
              else verify_tree(manifest, destination) if operation == 'verify'
              else (_ for _ in ()).throw(ValueError('Unknown operation')))
    print(json.dumps(result, indent=2))
