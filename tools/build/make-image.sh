#!/bin/bash
# Run only in the dedicated packaging container. Never accepts a host disk.
set -euo pipefail
stage=$(readlink -f "$1")
boot_mib=${2:-32}
case "$boot_mib" in 32|100) ;; *) echo 'Boot partition size must be 32 or 100 MiB' >&2; exit 1;; esac
case "$stage" in /build/couti-stage-*) ;; *) echo 'Invalid staging directory' >&2; exit 1;; esac
[ -d "$stage/bootfs" ]
root=/build/Couti
image=$stage/couti-usb.img
[ ! -e "$image" ]
# Audits and boot tests are opt-in; packaging itself does not run tests.
if [ "${COUTI_RUN_AUDITS:-0}" = 1 ]; then
    python3 /source/tools/check_boot_branding.py --artifacts "$stage/bootfs"
fi
python3 - "$image" "$boot_mib" <<'PY'
import struct, sys
def chs(lba):
    cylinder, rem = divmod(lba, 255 * 63)
    head, sector = divmod(rem, 63)
    return bytes((head, sector + 1 | ((cylinder >> 8) << 6), cylinder & 255))
mbr = bytearray(512)
boot_size = int(sys.argv[2]) * 2048
boot_start = 524288 - boot_size
for index, (start, size, kind, active) in enumerate(((2048, boot_start - 2048, 7, 128), (boot_start, boot_size, 239, 0))):
    offset = 446 + index * 16
    mbr[offset:offset + 16] = bytes((active,)) + chs(start) + bytes((kind,)) + chs(start + size - 1) + struct.pack('<II', start, size)
mbr[510:] = b'\x55\xaa'
with open(sys.argv[1], 'xb') as stream:
    stream.write(mbr)
    stream.truncate(256 * 1024 * 1024)
PY
loop=$(losetup --find --show --partscan "$image")
mountdir=$stage/mount
mkdir "$mountdir"
cleanup() {
    mountpoint -q "$mountdir" && umount "$mountdir" || true
    losetup -d "$loop"
}
trap cleanup EXIT
for part in 1 2; do
    node=${loop}p$part
    if [ ! -b "$node" ]; then
        read major minor < <(tr : ' ' < "/sys/class/block/${node#/dev/}/dev")
        mknod "$node" b "$major" "$minor"
    fi
done
mkfs.vfat -F 32 -n COUTI -s 1 "${loop}p1"
if [ "$boot_mib" = 100 ]; then
    mkfs.vfat -F 32 -n COUTI -s 1 "${loop}p2"
else
    mkfs.vfat -F 16 -n COUTIEFI -s 1 "${loop}p2"
fi
/build/grub-bios-tools/sbin/grub-bios-setup --skip-fs-probe \
    --directory="$root/INSTALL/grub/i386-pc" "$loop"
mount "${loop}p2" "$mountdir"
# Keep the main config near the front of FAT, as expected by the installers.
mkdir "$mountdir/grub"
cp "$stage/bootfs/grub/grub.cfg" "$mountdir/grub/"
cp -r "$stage/bootfs/." "$mountdir/"
sync
umount "$mountdir"
mkdir "$stage/boot" "$stage/ventoy"
dd if="$loop" of="$stage/boot/boot.img" bs=512 count=1 status=none
dd if="$loop" of="$stage/boot/core.img" bs=512 count=2047 skip=1 status=none
dd if="${loop}p2" of="$stage/ventoy/ventoy.disk.img" bs=1M count="$boot_mib" status=none
xz --check=crc32 "$stage/boot/core.img" "$stage/ventoy/ventoy.disk.img"
# A random disk UUID is part of the loader/OS protocol.
dd if=/dev/urandom of="$loop" bs=1 count=16 seek=384 conv=notrunc status=none
sync
echo "Couti disk image and installer payloads: $stage"
