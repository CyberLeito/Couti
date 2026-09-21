#!/usr/bin/env python3
"""Give an assembled boot filesystem Couti names (not the source/toolchain ABI)."""
import argparse
from pathlib import Path
import re


def rename_boot_files(boot):
    # Children first, so renaming a parent cannot invalidate a pending path.
    # Only directory entries change; opaque firmware and initramfs bytes stay intact.
    paths = sorted(boot.rglob('*'), key=lambda path: len(path.parts), reverse=True)
    for path in paths:
        name = re.sub(r'ventoy|vtoy', 'couti', path.name, flags=re.IGNORECASE)
        if name != path.name:
            target = path.with_name(name)
            if target.exists():
                raise FileExistsError('Refusing to overwrite ' + str(target))
            path.rename(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bootfs', type=Path)
    args = parser.parse_args()
    boot = args.bootfs.resolve()
    if not (boot / 'grub/grub.cfg').is_file() or not (boot / 'EFI/BOOT').is_dir():
        raise SystemExit('Expected an assembled Couti boot filesystem')
    rename_boot_files(boot)
