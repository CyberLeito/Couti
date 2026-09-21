#!/bin/bash
set -euo pipefail
root=/build/Couti
export PATH=/opt/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:/opt/mips-loongson-gcc7.3-linux-gnu/2019.06-29/bin:$PATH
mkdir -p "$root/GRUB2/SRC" "$root/GRUB2/NBP" /build/logs
src=$root/GRUB2/SRC/grub-2.04
if [ ! -d "$src" ]; then
    tar -xf /downloads/grub-2.04.tar.xz -C "$root/GRUB2/SRC"
    cp -a "$root/GRUB2/MOD_SRC/grub-2.04/." "$src/"
fi
cd "$src"
./autogen.sh > /build/logs/grub-autogen.log 2>&1
for target in "$@"; do
    echo "Building GRUB $target"
    make distclean >/dev/null 2>&1 || true
    args=(--prefix="$root/GRUB2/INSTALL/")
    case "$target" in
        x86_64-efi) args+=(--target=x86_64 --with-platform=efi); install_arg=uefi ;;
        i386-efi) args+=(--target=i386 --with-platform=efi); install_arg=i386efi ;;
        i386-pc) args+=(--target=i386 --with-platform=pc); install_arg='' ;;
        arm64-efi)
            args+=(--target=aarch64 --with-platform=efi --host=x86_64-linux-gnu
                HOST_CC=gcc BUILD_CC=gcc TARGET_CC=aarch64-linux-gnu-gcc
                TARGET_OBJCOPY=aarch64-linux-gnu-objcopy TARGET_STRIP=aarch64-linux-gnu-strip
                TARGET_NM=aarch64-linux-gnu-nm TARGET_RANLIB=aarch64-linux-gnu-ranlib)
            install_arg=arm64 ;;
        mips64el-efi)
            args+=(--target=mips64el --with-platform=efi --host=x86_64-linux-gnu
                HOST_CC=gcc BUILD_CC=gcc
                'TARGET_CC=mips-linux-gnu-gcc -mabi=64 -Wno-error=cast-align -Wno-error=misleading-indentation'
                TARGET_OBJCOPY=mips-linux-gnu-objcopy TARGET_STRIP=mips-linux-gnu-strip
                TARGET_NM=mips-linux-gnu-nm TARGET_RANLIB=mips-linux-gnu-ranlib)
            install_arg=mips64el ;;
        *) echo "Unknown GRUB target: $target" >&2; exit 1 ;;
    esac
    log=/build/logs/grub-$target.log
    (
        ./configure "${args[@]}" || exit 1
        make -j8 || exit 1
        bash install.sh "$install_arg"
    ) > "$log" 2>&1 || { tail -n 60 "$log"; exit 1; }
    echo "GRUB $target complete"
done
