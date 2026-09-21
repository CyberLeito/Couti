#!/bin/bash
set -euo pipefail
export PATH=/opt/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:/opt/aarch64--uclibc--stable-2020.08-1/bin:/opt/mips-loongson-gcc7.3-linux-gnu/2019.06-29/bin:$PATH
cd /build/Couti
mkdir -p /build/logs
if [ "${COUTI_RUN_AUDITS:-0}" = 1 ]; then
    python3 tools/check_boot_branding.py
fi

for component in GRUB2 IPXE EDK2; do
    case "$component" in
        GRUB2) script=buildgrub.sh ;;
        IPXE) script=buildipxe.sh ;;
        EDK2) script=buildedk.sh ;;
    esac
    echo "Building $component (log: /build/logs/$component.log)"
    (cd "$component" && bash "$script") > "/build/logs/$component.log" 2>&1 || {
        tail -n 80 "/build/logs/$component.log"
        exit 1
    }
done
echo 'GRUB, iPXE and EDK2 boot components rebuilt.'
