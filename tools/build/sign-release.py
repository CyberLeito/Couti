#!/usr/bin/env python3
"""Sign rebuilt Couti EFI payloads, retaining the unmodified Microsoft shim."""
import argparse
import hashlib
import lzma
from pathlib import Path
import shutil
import struct
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('stage', type=Path)
parser.add_argument('--keys', type=Path, default=Path('/keys'))
args = parser.parse_args()
boot = args.stage.resolve() / 'bootfs'
key = args.keys / 'couti-secure-boot.key'
cert = args.keys / 'couti-secure-boot.pem'
if not key.is_file() or not cert.is_file():
    raise SystemExit('Create the Couti key and certificate before signing')


def security_size(path):
    data = path.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('Expected a PE/COFF executable: ' + str(path))
    pe = struct.unpack_from('<I', data, 60)[0]
    magic = struct.unpack_from('<H', data, pe + 24)[0]
    directory = pe + 24 + (112 if magic == 0x20b else 96)
    return struct.unpack_from('<I', data, directory + 36)[0]


def sign(path):
    compressed = path.suffix == '.xz'
    working = path.with_suffix('.unsigned.efi') if compressed else path
    if compressed:
        working.write_bytes(lzma.decompress(path.read_bytes()))
    # Replace old signatures with the Couti identity through the signing tool.
    while security_size(working):
        subprocess.run(['sbattach', '--remove', str(working)], check=True)
    signed = working.with_suffix('.signed.efi')
    subprocess.run(['sbsign', '--key', str(key), '--cert', str(cert),
                    '--output', str(signed), str(working)], check=True)
    if compressed:
        path.write_bytes(lzma.compress(signed.read_bytes(), check=lzma.CHECK_CRC32))
        working.unlink()
        signed.unlink()
    else:
        signed.replace(path)
    print('Signed ' + str(path.relative_to(boot)), flush=True)


for arch in ('x64', 'ia32'):
    sign(boot / 'EFI/BOOT' / ('grub' + arch + '_real.efi'))
for prefix in ('iso9660', 'udf', 'couti', 'coutiutil'):
    for arch in ('x64', 'ia32', 'aa64'):
        sign(boot / 'couti' / (prefix + '_' + arch + '.efi'))
for name in ('wimboot.i386.efi.xz', 'wimboot.x86_64.xz'):
    sign(boot / 'couti' / name)

# This hash binds the shim adapter to this exact signed GRUB build. Embed it
# before signing the adapter, exactly as in the upstream packaging sequence.
adapter = boot / 'EFI/BOOT/fbx64.efi'
data = adapter.read_bytes()
marker = b'&' * 32
if data.count(marker) != 1:
    raise ValueError('Expected one unsigned shim hash placeholder')
grub_hash = hashlib.sha256((boot / 'EFI/BOOT/grubx64_real.efi').read_bytes()).digest()
adapter.write_bytes(data.replace(marker, grub_hash))
sign(adapter)
subprocess.run(['openssl', 'x509', '-in', str(cert), '-outform', 'DER',
                '-out', str(boot / 'ENROLL_THIS_KEY_IN_MOKMANAGER.cer')], check=True)
shutil.copyfile(boot / 'ENROLL_THIS_KEY_IN_MOKMANAGER.cer', args.stage / 'Couti-Secure-Boot.cer')
print('Couti Secure Boot payload signing complete. No boot tests were run.')
