#!/usr/bin/env python3
"""Assemble a Couti boot partition from the isolated rebuild."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('--secure-boot', action='store_true')
args = parser.parse_args()
source = Path('/build/Couti/INSTALL')
dest = args.destination.resolve()
if dest.exists() or dest.parent != Path('/build'):
    raise SystemExit('Use a new staging directory directly under /build')
dest.mkdir()
boot = dest / 'bootfs'
boot.mkdir()
for folder in ('grub', 'ventoy', 'EFI'):
    shutil.copytree(source / folder, boot / folder)
for folder in ('menu', 'help'):
    with tarfile.open(str(boot / 'grub' / (folder + '.tar.gz')), 'w:gz') as archive:
        archive.add(str(boot / 'grub' / folder), arcname='./' + folder)
    shutil.rmtree(boot / 'grub' / folder)
menu = source / 'grub/menu'
entries = []
for path in sorted(menu.glob('*.json'), key=lambda p: (p.stem != 'zh_CN', p.stem)):
    label = json.loads(path.read_text(encoding='utf-8-sig'))['VTLANG_LANGUAGE_NAME']
    # Match the upstream language menu format while keeping text UTF-8.
    entries += ['menuentry "{}  -  {}" --class=menu_lang_item --class=debug_menu_lang --class=F5tool {{'.format(path.stem, label),
                '    vt_load_menu_lang ' + path.stem, '}']
entries += ['menuentry "$VTLANG_RETURN_PREVIOUS" --class=coutiret VTOY_RET {',
            '    echo "Return ..."', '}']
(boot / 'grub/menulang.cfg').write_text('\n'.join(entries) + '\n', encoding='utf-8')

# A plain UEFI build boots the freshly compiled loader directly. It must not
# carry upstream shims, embedded trust identities or enrollment certificates.
efi = boot / 'EFI/BOOT'
if not args.secure_boot:
    for arch in ('x64', 'ia32'):
        shutil.copyfile(efi / ('grub' + arch + '_real.efi'), efi / ('BOOT' + arch.upper() + '.EFI'))
    for path in efi.iterdir():
        if path.name.upper() not in ('BOOTX64.EFI', 'BOOTIA32.EFI', 'BOOTAA64.EFI', 'BOOTMIPS.EFI'):
            path.unlink()
for path in (boot / 'grub/i386-pc').glob('*.img'):
    path.unlink()
(boot / 'tool').mkdir()
for arch in ('i386', 'x86_64', 'aarch64'):
    # The runtime hook reserves these placeholders exactly as the upstream
    # packer does. Real filesystem helpers are supplied by the booted image.
    data = (source / 'tool' / arch / 'vtoycli').read_bytes()[:16384]
    (boot / 'tool' / ('mount.exfat-fuse_' + arch)).write_bytes(data)
shutil.copyfile(source / 'tool/create_ventoy_iso_part_dm.sh', boot / 'tool/create_ventoy_iso_part_dm.sh')
subprocess.run([sys.executable, str(Path(__file__).with_name('couti-boot-layout.py')), str(boot)], check=True)
print(dest)
