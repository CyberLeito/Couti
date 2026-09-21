#!/usr/bin/env python3
"""Localize display literals in the bundled unsigned BSD binaries.

These kernels require separate native BSD toolchains for each historical ABI.
This fallback changes only reviewed, fixed-length diagnostic strings. It leaves
code, relocations, symbol names, device paths and filesystem offsets unchanged.
Never use it on signed EFI files. Native BSD rebuilds remain preferable.
"""
import hashlib
import argparse
import json
import lzma
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
# Full phrases avoid touching ABI identifiers, property keys and device paths.
PHRASES = (
    b'ventoy disk ', b'ventoy remount ', b'ventoy alias ',
    b'ventoy segment', b'ventoy seg ', b'ventoy map data ',
    b'ventoy.disksize:', b'ventoy.diskuuid:', b'devalias for ventoy ',
    b'GEOM ventoy support', b'GEOM_VENTOY stuff', b'GEOM_VENTOY Data',
    b'Ventoy Init Start',
)


def rodata_ranges(data):
    if data[:4] != b'\x7fELF' or data[5] != 1:
        raise ValueError('Expected a little-endian unsigned ELF')
    wide = data[4] == 2
    shoff = struct.unpack_from('<Q' if wide else '<I', data, 40 if wide else 32)[0]
    stride, count, names_index = struct.unpack_from('<HHH', data, 58 if wide else 46)
    fmt = '<IIQQQQIIQQ' if wide else '<IIIIIIIIII'
    sections = [struct.unpack_from(fmt, data, shoff + i * stride) for i in range(count)]
    names = sections[names_index]
    table = data[names[4]:names[4] + names[5]]
    ranges = []
    for section in sections:
        name = table[section[0]:].split(b'\0', 1)[0]
        if name.startswith(b'.rodata'):
            ranges.append((section[4], section[4] + section[5]))
    return ranges


def localize(data):
    ranges = rodata_ranges(data)
    result = bytearray(data)
    changes = []
    for phrase in PHRASES:
        for match in re.finditer(re.escape(phrase), data):
            start, end = match.span()
            if not any(lo <= start and end <= hi for lo, hi in ranges):
                raise ValueError('Diagnostic outside read-only data: ' + repr(phrase))
            # One padding space preserves every address, including suffix-pooled
            # strings. No executable code or terminating NUL is moved.
            replacement = re.sub(b'ventoy', b'Couti ', phrase, flags=re.I)
            assert len(replacement) == len(phrase)
            result[start:end] = replacement
            changes.append({'offset': start, 'old': phrase.decode(), 'new': replacement.decode()})
    assert len(result) == len(data)
    return bytes(result), changes


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', help='read original payloads from this Git revision')
    args = parser.parse_args()
    report = []
    writes = []
    def original(path):
        if args.reference:
            return subprocess.check_output(['git', 'show', args.reference + ':' +
                                            path.relative_to(ROOT).as_posix()], cwd=ROOT)
        return path.read_bytes()
    base = ROOT / 'Unix/ventoy_unix'
    for path in sorted(base.rglob('geom_ventoy.ko.xz')):
        raw = lzma.decompress(original(path))
        branded, changes = localize(raw)
        if changes:
            if lzma.decompress(path.read_bytes()) not in (raw, branded):
                raise ValueError('Unrecognized local changes: ' + str(path))
            writes.append((path, lzma.compress(branded, check=lzma.CHECK_CRC32)))
            report.append({'path': path.relative_to(ROOT).as_posix(),
                           'original_elf_sha256': digest(raw),
                           'branded_elf_sha256': digest(branded), 'changes': changes})

    init = base / 'DragonFly/sbin/init'
    raw = original(init)
    branded, changes = localize(raw)
    if changes:
        image = ROOT / 'INSTALL/ventoy/dragonfly.mfs.xz'
        filesystem = lzma.decompress(original(image))
        updated = filesystem
        # UFS stores a file in separate blocks. Match the diagnostic and its
        # surrounding bytes against the known ELF instead of assuming contiguous
        # on-disk storage for the entire executable.
        for change in changes:
            offset = change['offset']
            old = change['old'].encode()
            context = raw[offset - 16:offset + len(old) + 16]
            if filesystem.count(context) != 1:
                raise ValueError('Expected exactly one matching init diagnostic in DragonFly image')
            image_offset = filesystem.index(context) + 16
            change['filesystem_offset'] = image_offset
            updated = (updated[:image_offset] + change['new'].encode() +
                       updated[image_offset + len(old):])
        assert len(updated) == len(filesystem)
        if init.read_bytes() not in (raw, branded):
            raise ValueError('Unrecognized local changes to DragonFly init')
        if lzma.decompress(image.read_bytes()) not in (filesystem, updated):
            raise ValueError('Unrecognized local changes to DragonFly image')
        writes += [(image, lzma.compress(updated, check=lzma.CHECK_CRC32)), (init, branded)]
        report.append({'path': init.relative_to(ROOT).as_posix(),
                       'original_elf_sha256': digest(raw), 'branded_elf_sha256': digest(branded),
                       'original_filesystem_sha256': digest(filesystem),
                       'branded_filesystem_sha256': digest(updated), 'changes': changes})
    if report:
        for path, data in writes:
            path.write_bytes(data)
        (ROOT / 'tools/build/legacy-bsd-branding.json').write_text(
            json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Localized {} unsigned legacy BSD payloads.'.format(len(report)))


if __name__ == '__main__':
    main()
