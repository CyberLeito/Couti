#!/bin/bash
set -eo pipefail
root=/build/Couti
export PATH=/opt/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:$PATH
mkdir -p /build/logs
cd "$root/EDK2"
if [ ! -d edk2-edk2-stable201911 ]; then
    unzip -q /downloads/edk2-stable201911.zip
    cp -a edk2_mod/edk2-edk2-stable201911/. edk2-edk2-stable201911/
fi
make -j8 -C edk2-edk2-stable201911/BaseTools > /build/logs/edk-tools.log 2>&1
for target in "$@"; do
    echo "Building EDK2 $target"
    case "$target" in
        x64) args=() ;;
        ia32) args=(ia32) ;;
        aa64) args=(aa64) ;;
        shim) bash build_shim.sh > /build/logs/edk-shim.log 2>&1; continue ;;
        *) echo "Unknown EDK2 target: $target" >&2; exit 1 ;;
    esac
    bash build.sh "${args[@]}" > "/build/logs/edk-$target.log" 2>&1 || {
        tail -n 60 "/build/logs/edk-$target.log"; exit 1;
    }
    echo "EDK2 $target complete"
done
