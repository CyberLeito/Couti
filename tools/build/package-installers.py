#!/usr/bin/env python3
"""Package existing signed boot images and installers; does not run tests."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('stage', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--windows-exe', type=Path, required=True)
parser.add_argument('--vhd-helper', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
install = repo / 'INSTALL'
version = '1.1.17'
name = 'couti-' + version
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
work = out / name
if work.exists():
    raise SystemExit('Use an output directory without an existing ' + name)
work.mkdir()
for folder in ('boot', 'ventoy'):
    shutil.copytree(args.stage / folder, work / folder)
(work / 'ventoy/version').write_text(version + '\n', encoding='ascii')
shutil.copyfile(repo / 'LANGUAGES/languages.json', work / 'ventoy/languages.json')
shutil.copyfile(args.stage / 'Couti-Secure-Boot.cer', work / 'Couti-Secure-Boot.cer')
shutil.copyfile(repo / 'DOC/USB-START-HERE.md', work / 'START-HERE.md')
shutil.copyfile(repo / 'DOC/CoutiTheme.md', work / 'THEME-GUIDE.md')
shutil.copyfile(repo / 'COPYING', work / 'COPYING')
shutil.copytree(repo / 'License', work / 'License')

usb = work / 'USB-FILES/ventoy'
usb.mkdir(parents=True)
shutil.copyfile(args.vhd_helper, usb / 'ventoy_vhdboot.img')
(usb / 'ventoy.json').write_text(json.dumps({
    'control': [{'VTOY_SECURE_BOOT_POLICY': '0'}, {'VTOY_DEFAULT_MENU_MODE': '0'}]
}, indent=4) + '\n', encoding='utf-8')

info = {
    'name': 'Couti', 'version': version, 'built_at_utc': datetime.now(timezone.utc).isoformat(),
    'firmware_boot_tests': 'Not run; user requested to perform testing personally.',
    'boot_filesystem': {'volume_label': 'COUTIEFI', 'payload_directory': '/couti',
                        'names': 'Couti filenames; internal OS/plugin ABI identifiers retained',
                        'migration': 'Use the installer Update operation; do not rename old files manually'},
    'boot_ui': {'start_view': 'Folders',
                'home_partition': 'Largest supported data partition on the boot drive; excludes the boot partition.',
                'partition_chooser': 'Back entry at the root, or F2',
                'shortcuts': {'F1': 'Help', 'F2': 'Folders', 'F3': 'Tools',
                              'F4': 'LocalBoot', 'F5': 'Power Menu'},
                'F6': 'Disabled', 'F7': 'Disabled', 'language_shortcuts': 'Removed',
                'font': 'DejaVu Sans (18-pixel menu, 16-pixel dock, 14-pixel status)',
                'theme': 'Supplied sample_slack artwork with editable PNG shortcut icons and labels below'},
    'secure_boot': {'target': 'x86-64 UEFI', 'identity': 'Couti Secure Boot',
                    'enrollment': 'Enroll the provided DER certificate through MOK Manager.',
                    'payload_policy': 'Compatibility (0): accepts unsigned payloads after the signed loader.',
                    'certificate_sha256': hashlib.sha256((work / 'Couti-Secure-Boot.cer').read_bytes()).hexdigest()},
    'vhd_helper': {'source': 'https://github.com/ventoy/vhdiso/releases/tag/v3.0',
                   'template': 'Win10Based/ventoy_vhdboot.img',
                   'upstream_zip_sha256': '6af371a1ee457c75fcbe864e08b5f5d4583f0ef838713fec2920d3d62176b686',
                   'image_sha256': hashlib.sha256(args.vhd_helper.read_bytes()).hexdigest()},
    'rebuilds': ['GRUB BIOS/IA32/x86-64/ARM64/MIPS64EL', 'EDK2 IA32/x86-64/ARM64 and x64 shim adapter',
                 'iPXE BIOS', 'VtoyTool all four architectures', 'Windows 32/64-bit boot helpers',
                 'Windows installer', 'initramfs archives'],
    'legacy_bsd': 'Fixed-length read-only diagnostic localization; native BSD ABI builds were retained.',
    'private_key_included': False
}
(work / 'BUILD-INFO.json').write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8')
shutil.copyfile(args.windows_exe, work / 'Couti2Disk.exe')
windows = out / (name + '-windows.zip')
with zipfile.ZipFile(windows, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(work.rglob('*')):
        if path.is_file():
            archive.write(path, arcname=path.relative_to(out).as_posix())

# CLI-only Linux package avoids distributing unrelated prebuilt GUI programs.
linux = out / (name + '-linux')
shutil.copytree(work, linux / name)
linux_root = linux / name
(linux_root / 'Couti2Disk.exe').unlink()
for filename in ('Couti2Disk.sh', 'Ventoy2Disk.sh', 'CreatePersistentImg.sh', 'ExtendPersistentImg.sh'):
    path = linux_root / filename
    path.write_bytes((install / filename).read_bytes().replace(b'\r\n', b'\n'))
    path.chmod(0o755)
(linux_root / 'tool').mkdir()
for filename in ('ventoy_lib.sh', 'VentoyWorker.sh'):
    path = linux_root / 'tool' / filename
    path.write_bytes((install / 'tool' / filename).read_bytes().replace(b'\r\n', b'\n'))
    path.chmod(0o755)
shutil.copyfile(work / 'Couti-Secure-Boot.cer', linux_root / 'tool/ENROLL_THIS_KEY_IN_MOKMANAGER.cer')
for arch in ('x86_64', 'i386', 'aarch64', 'mips64el'):
    target = linux_root / 'tool' / arch
    target.mkdir()
    for path in (install / 'tool' / arch).iterdir():
        if path.is_file() and path.name not in ('V2DServer', 'Plugson', 'vlnk') and not path.name.startswith('Ventoy2Disk.'):
            shutil.copyfile(path, target / path.name)
            (target / path.name).chmod(0o755)
linux_archive = out / (name + '-linux.tar.gz')
def linux_modes(member):
    relative = Path(member.name).relative_to(name)
    executable = (member.isdir() or member.name.endswith('.sh') or
                  (len(relative.parts) == 3 and relative.parts[0] == 'tool'))
    member.mode = 0o755 if executable else 0o644
    member.uid = member.gid = 0
    member.uname = member.gname = 'root'
    return member
with tarfile.open(str(linux_archive), 'w:gz') as archive:
    archive.add(str(linux_root), arcname=name, filter=linux_modes)

# Checksums describe the delivered files; this is not a boot test.
artifacts = (windows, linux_archive)
(out / 'SHA256SUMS.txt').write_text(''.join(
    hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in artifacts), encoding='ascii')
for path in artifacts:
    print(str(path) + ' (' + str(path.stat().st_size) + ' bytes)')
