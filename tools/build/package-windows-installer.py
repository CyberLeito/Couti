#!/usr/bin/env python3
"""Package the x86 Couti Installer with signed boot files; no tests or disk operations."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import lzma
from pathlib import Path
import shutil
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('stage', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--vhd-helper', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
work = out / 'couti-installer-x86'
if work.exists():
    raise SystemExit('Use an output directory without an existing couti-installer-x86 folder')
work.mkdir()
shutil.copyfile(repo / 'INSTALL/Couti2Disk.exe', work / 'Couti2Disk.exe')
shutil.copytree(args.stage / 'bootfs', work / 'boot-files')
shutil.copyfile(args.vhd_helper, work / 'boot-files/couti/couti_vhdboot.img')
(work / 'boot').mkdir()
shutil.copyfile(args.stage / 'boot/boot.img', work / 'boot/boot.img')
(work / 'boot/core.img').write_bytes(lzma.decompress((args.stage / 'boot/core.img.xz').read_bytes()))
shutil.copyfile(args.stage / 'Couti-Secure-Boot.cer', work / 'Couti-Secure-Boot.cer')
shutil.copyfile(repo / 'DOC/CoutiInstaller.md', work / 'START-HERE.md')
shutil.copyfile(repo / 'DOC/CoutiTheme.md', work / 'THEME-GUIDE.md')
shutil.copyfile(repo / 'COPYING', work / 'COPYING')
shutil.copytree(repo / 'License', work / 'License')
info = {
    'application': 'Couti Installer', 'architecture': 'x86',
    'installer_revision': '2026-09-21-format-init-fix',
    'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'host': 'Windows 10/11 with .NET Framework 4.x and the Windows Storage module; administrator privileges required',
    'boot_partition': {'count': 1, 'preferred_partition': 2, 'size_bytes': 100 * 1024 * 1024, 'filesystem': 'FAT32', 'label': 'COUTI'},
    'format_data_partition': {'partition': 1, 'filesystem': 'NTFS', 'label': 'Gabulhi'},
    'default': 'Preserve data and labels. Use unallocated space or shrink an eligible NTFS partition on the selected physical disk.',
    'secure_boot': {'target': 'x86-64 UEFI', 'certificate': 'Couti-Secure-Boot.cer', 'enrollment': 'MOK enrollment may be required', 'payload_policy': 'Compatibility (0)', 'certificate_sha256': hashlib.sha256((work / 'Couti-Secure-Boot.cer').read_bytes()).hexdigest()},
    'builds': ['GRUB BIOS/IA32/x86-64/ARM64/MIPS64EL', 'EDK2 IA32/x86-64/ARM64 and shim adapter', 'Windows boot helpers x86/x64', 'Linux boot helpers and initramfs', 'Couti Installer x86'],
    'tests': 'No agent-run tests. This corrected installer has not been executed against a disk; the preceding build failed during user testing.',
    'private_key_included': False
}
(work / 'BUILD-INFO.json').write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8')

archives = []
for filename, directory, prefix in (
    ('couti-installer-x86.zip', work, 'couti-installer-x86'),
    ('couti-boot-files-100mb.zip', work / 'boot-files', ''),
):
    archive_path = out / filename
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(directory.rglob('*')):
            if path.is_file():
                archive.write(path, (Path(prefix) / path.relative_to(directory)).as_posix())
    archives.append(archive_path)
(out / 'COUTI-INSTALLER-SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in archives), encoding='ascii')
for path in archives:
    print(str(path) + ' (' + str(path.stat().st_size) + ' bytes)')
