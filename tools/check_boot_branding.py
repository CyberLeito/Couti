#!/usr/bin/env python3
"""Audit Couti's own boot UI and reject known upstream boot payloads.

Internal ABI names and copyright notices are deliberately not branding checks.
This is a regression check, not a substitute for booting the finished image.
"""
import argparse
import gzip
import json
import lzma
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
OLD = re.compile(r"ventoy", re.I)
LITERAL = r'(?:L?"(?:[^"\\]|\\.)*"\s*)+'
OUTPUT = re.compile(
    r'\b(?:grub_printf|grub_puts|printf|Print|AsciiPrint|vLog|vErr|'
    r'debug|vdebug|Log|ventoy_debug|G_DEBUG)\s*\(\s*(' + LITERAL + ')', re.S)
BSD_OUTPUT = re.compile(r'\bG_VENTOY_(?:DEBUG|LOGREQ)\s*\([^,]*,\s*(' + LITERAL + ')', re.S)
C_ROOTS = (
    'GRUB2/MOD_SRC', 'EDK2/edk2_mod', 'IPXE/ipxe_mod_code',
    'Unix/ventoy_unix_src', 'vtoyjump', 'VtoyTool', 'wimboot',
)
# vtoydm's stdout is a machine-readable protocol consumed by initramfs hooks.
OUTPUT_PROTOCOLS = {('VtoyTool/vtoydm.c', '"VENTOY_ISO_LABEL %s\\n"')}
# Literal messages that distinguish old payloads from rebuilt Couti payloads.
# Do not match internal symbols, filenames, ABI magic, or copyright notices.
STALE = re.compile(
    rb'Unofficial Ventoy|Ventoy scanning files|standard Ventoy device|'
    rb'Ventoy Secure Policy|Ventoy Security Boot Violation|Ventoy hash check|'
    rb'ventoy not ready|VENTOY DEBUG|VENTOY WIMBOOT|Ventoy Init Start|'
    rb'ventoy boot failed|load from Ventoy again|Ventoy LiveCD|'
    rb'Failed to parse ventoy seg|Ventoy2Disk permission denied', re.I)
BSD_STALE = re.compile(
    rb'ventoy (?:disk |remount |alias |segment|map data )|'
    rb'GEOM ventoy support|GEOM_VENTOY (?:stuff|Data)|'
    rb'ventoy\.(?:disksize|diskuuid):', re.I)
LIMIT = 64 * 1024 * 1024


def source_errors(root):
    errors = []
    for folder in ('INSTALL/grub/menu', 'INSTALL/grub/help'):
        for path in sorted((root / folder).glob('*')):
            if not path.is_file():
                continue
            text = path.read_text(encoding='utf-8-sig')
            if path.suffix == '.json':
                try:
                    json.loads(text)
                except ValueError as error:
                    errors.append(str(path.relative_to(root)) + ': ' + str(error))
            if OLD.search(text):
                errors.append(str(path.relative_to(root)) + ': old boot UI branding')
    for folder in C_ROOTS:
        for path in sorted((root / folder).rglob('*')):
            if path.suffix not in ('.c', '.h'):
                continue
            try:
                text = path.read_text(encoding='utf-8')
            except UnicodeError:
                continue
            if STALE.search(text.encode('utf-8')):
                errors.append(str(path.relative_to(root)) + ': old boot banner')
            for match in list(OUTPUT.finditer(text)) + list(BSD_OUTPUT.finditer(text)):
                if (path.relative_to(root).as_posix(), match[1].strip()) in OUTPUT_PROTOCOLS:
                    continue
                if OLD.search(match[1]):
                    line = text.count('\n', 0, match.start()) + 1
                    errors.append('{}:{}: old output literal'.format(path.relative_to(root), line))
    configs = list((root / 'INSTALL/grub').glob('*.cfg'))
    configs += [root / p for p in (
        'LiveCD/ISO/EFI/boot/grub.cfg', 'LiveCDGUI/ISO/EFI/boot/grub.cfg')]
    for path in configs:
        for line, text in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            if re.match(r'\s*(echo|menuentry|set VTOY_TEXT_MENU_VER=)', text):
                # Environment references are implementation details, not literal UI.
                literal = re.sub(r'\$\{?\w+\}?', '', text)
                if OLD.search(literal):
                    errors.append('{}:{}: old menu text'.format(path.relative_to(root), line))
    for folder in ('IMG/cpio', 'LiveCD/VTOY', 'LiveCDGUI/VTOY'):
        for path in (root / folder).rglob('*'):
            if path.is_file() and path.suffix not in ('.png', '.ico'):
                if STALE.search(path.read_bytes()):
                    errors.append(str(path.relative_to(root)) + ': old boot helper message')
    cfg = (root / 'INSTALL/grub/grub.cfg').read_text(encoding='utf-8')
    if 'set theme=$prefix/themes/couti/theme.txt' not in cfg:
        errors.append('Default boot theme is not Couti')
    theme = root / 'INSTALL/grub/themes/couti/theme.txt'
    text = theme.read_text(encoding='utf-8')
    if 'title-text: "Couti"' not in text or 'desktop-image:' in text:
        errors.append('Couti text theme is missing or uses an unaudited wallpaper')
    for image in re.findall(r'"([^"\n]+\.png)"', text):
        if not list(theme.parent.glob(image)):
            errors.append('Missing theme asset: ' + image)
    if (root / 'INSTALL/grub/themes/ventoy').exists():
        errors.append('Retired upstream theme is still included')
    return errors


def payloads(name, data, depth=0):
    """Read compressed initramfs members without extracting executable files."""
    yield name, data
    if depth >= 8:
        raise ValueError('archive nesting exceeds audit limit: ' + name)
    if data.startswith(b'\xfd7zXZ\x00'):
        decoder = lzma.LZMADecompressor()
        decoded = decoder.decompress(data, max_length=LIMIT + 1)
        if len(decoded) > LIMIT or not decoder.eof:
            raise ValueError('XZ payload exceeds audit limit: ' + name)
        yield from payloads(name + ':xz', decoded, depth + 1)
    elif data.startswith(b'\x1f\x8b'):
        import io
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            decoded = stream.read(LIMIT + 1)
        if len(decoded) > LIMIT:
            raise ValueError('gzip payload exceeds audit limit: ' + name)
        yield from payloads(name + ':gzip', decoded, depth + 1)
    elif data.startswith((b'070701', b'070702')):
        offset = 0
        while offset + 110 <= len(data):
            header = data[offset:offset + 110]
            if header[:6] not in (b'070701', b'070702'):
                raise ValueError('invalid newc header: ' + name)
            size = int(header[54:62], 16)
            namesize = int(header[94:102], 16)
            endname = offset + 110 + namesize
            if namesize < 1 or endname > len(data):
                raise ValueError('invalid newc name: ' + name)
            member = data[offset + 110:endname - 1].decode('utf-8', 'replace')
            start = (endname + 3) & ~3
            end = start + size
            if end > len(data):
                raise ValueError('truncated newc member: ' + name)
            if member == 'TRAILER!!!':
                break
            if size:
                yield from payloads(name + ':' + member, data[start:end], depth + 1)
            offset = (end + 3) & ~3


def artifact_errors(root):
    errors = []
    for folder in ('EFI', 'ventoy', 'grub'):
        base = root / folder
        if not base.is_dir():
            errors.append('Missing boot payload directory: ' + str(base))
            continue
        for path in sorted(base.rglob('*')):
            if not path.is_file():
                continue
            raw = path.read_bytes()
            # Authenticode's certificate table is a file offset, not a PE RVA.
            # Inspect only that table so debug paths and ABI strings don't fail.
            if raw.startswith(b'MZ') and len(raw) >= 64:
                pe = struct.unpack_from('<I', raw, 60)[0]
                if pe + 160 <= len(raw) and raw[pe:pe + 4] == b'PE\x00\x00':
                    magic = struct.unpack_from('<H', raw, pe + 24)[0]
                    directory = pe + 24 + (112 if magic == 0x20b else 96)
                    if directory + 40 <= len(raw):
                        offset, size = struct.unpack_from('<II', raw, directory + 32)
                        certificate = raw[offset:offset + size].replace(b'\x00', b'').lower()
                        if size and b'ventoy' in certificate:
                            errors.append(str(path.relative_to(root)) + ': upstream signing certificate')
            for name, data in payloads(str(path.relative_to(root)), raw):
                # PE firmware messages can use UTF-16LE instead of ASCII.
                for candidate in (data, data.replace(b'\x00', b'')):
                    match = STALE.search(candidate)
                    if not match and data.startswith(b'\x7fELF'):
                        match = BSD_STALE.search(candidate)
                    if match:
                        errors.append(name + ': stale branding: ' + match[0].decode('ascii'))
                        break
    # Enrollment displays the subject/issuer. Old DER certificates must not ship.
    for path in root.rglob('*.cer'):
        data = path.read_bytes().replace(b'\x00', b'').lower()
        if b'ventoy' in data:
            errors.append(str(path.relative_to(root)) + ': upstream enrollment certificate')
    return sorted(set(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path,
                        help='also audit an assembled boot partition before signing/packaging')
    args = parser.parse_args()
    try:
        errors = source_errors(ROOT)
        if args.artifacts:
            errors.extend(artifact_errors(args.artifacts))
    except (OSError, ValueError, EOFError, lzma.LZMAError) as error:
        print('Couti branding audit could not inspect a payload: ' + str(error))
        return 1
    if errors:
        print('Couti branding audit FAILED:')
        for error in errors:
            print('  ' + error)
        return 1
    print('Couti boot branding source audit passed.' if not args.artifacts
          else 'Couti source and known boot-payload branding checks passed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
